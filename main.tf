resource "aws_ecs_capacity_provider" "ecs" {
  name = var.service_name

  auto_scaling_group_provider {
    auto_scaling_group_arn         = local.arg_arn
    managed_termination_protection = var.managed_termination_protection ? "ENABLED" : "DISABLED"
    managed_draining               = var.managed_draining ? "ENABLED" : "DISABLED"

    managed_scaling {
      maximum_scaling_step_size = 10
      minimum_scaling_step_size = 1
      status                    = "ENABLED"
      # https://repost.aws/questions/QU-SweEQPqR2evZ-n_KaUL0A/ecs-understanding-of-capacityproviderreservation
      target_capacity        = 100
      instance_warmup_period = 300
    }
  }
  tags = merge(
    local.default_module_tags,
    {
      VantaContainsUserData : false
      VantaContainsEPHI : false
    }
  )
}

resource "aws_ecs_cluster_capacity_providers" "ecs" {
  cluster_name = aws_ecs_cluster.ecs.name
  capacity_providers = [
    aws_ecs_capacity_provider.ecs.name
  ]
  default_capacity_provider_strategy {
    base              = 1
    weight            = 100
    capacity_provider = aws_ecs_capacity_provider.ecs.name
  }
}

resource "aws_ecs_cluster" "ecs" {
  name = var.service_name
  setting {
    name  = "containerInsights"
    value = var.enable_container_insights ? "enabled" : "disabled"
  }
  tags = merge(
    local.default_module_tags,
    {
      VantaContainsUserData : false
      VantaContainsEPHI : false
    }
  )
}

resource "aws_ecs_task_definition" "ecs" {
  family = var.service_name
  container_definitions = jsonencode(
    [
      merge(
        {
          name      = var.service_name
          image     = var.docker_image
          cpu       = var.container_cpu
          memory    = var.container_memory
          essential = true
          portMappings = [
            {
              containerPort = var.container_port
            }
          ]
          healthCheck = {
            "retries" : 3,
            "command" : [
              "CMD-SHELL", var.container_healthcheck_command
            ],
            "timeout" : 5,
            "interval" : 30,
            "startPeriod" : null
          }
          logConfiguration = local.log_configuration
          environment      = var.task_environment_variables
          secrets          = var.task_secrets
          mountPoints = [
            for name, def in merge(var.task_efs_volumes, var.task_local_volumes) : {
              sourceVolume : name
              containerPath : def.container_path
            }
          ]
        },
        var.container_command != null ? { command : var.container_command } : {},
        var.dockerSecurityOptions != null ? { dockerSecurityOptions : var.dockerSecurityOptions } : {}
      )
    ]
  )
  execution_role_arn = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn      = var.task_role_arn
  ipc_mode           = var.task_ipc_mode

  dynamic "volume" {
    for_each = var.task_efs_volumes
    content {
      name = volume.key
      efs_volume_configuration {
        file_system_id = volume.value.file_system_id
      }
    }
  }
  dynamic "volume" {
    for_each = var.task_local_volumes
    content {
      name      = volume.key
      host_path = volume.value.host_path
    }
  }
  tags = merge(
    local.default_module_tags,
    {
      VantaContainsUserData : false
      VantaContainsEPHI : false
    }
  )
}

resource "aws_ecs_service" "ecs" {
  name                              = var.service_name
  cluster                           = aws_ecs_cluster.ecs.id
  task_definition                   = aws_ecs_task_definition.ecs.arn
  desired_count                     = var.task_desired_count
  health_check_grace_period_seconds = var.service_health_check_grace_period_seconds

  lifecycle {
    ignore_changes = [desired_count]
  }

  load_balancer {
    target_group_arn = local.target_group_arn
    container_name   = var.service_name
    container_port   = var.container_port
  }

  capacity_provider_strategy {
    base              = 1
    capacity_provider = aws_ecs_capacity_provider.ecs.name
    weight            = 100
  }

  depends_on = [
    aws_iam_role.ecs_task_execution_role,
    aws_iam_role_policy_attachment.ecs_task_execution_role_policy,
  ]
  tags = merge(
    {
      # need these tags for implicit dependency
      execution_role_arn : aws_ecs_task_definition.ecs.execution_role_arn
      target_group_arn : local.target_group_arn
      load_balancer_arn : local.load_balancer_arn
      backend_security_group : substr(
        base64encode(
          jsonencode(
            local.backend_security_group
          )
        ), 0, 256
      )
      instance_role_policy_name : local.instance_role_policy_name
      instance_role_policy_attachment : local.instance_role_policy_attachment
    },
    local.default_module_tags,
    {
      VantaContainsUserData : false
      VantaContainsEPHI : false
    }
  )
  timeouts {
    delete = "10m"
  }
}
