resource "aws_ecs_capacity_provider" "ecs" {
  name = var.service_name

  auto_scaling_group_provider {
    auto_scaling_group_arn         = module.pod.asg_arn
    managed_termination_protection = "ENABLED"

    managed_scaling {
      maximum_scaling_step_size = 10
      minimum_scaling_step_size = 1
      status                    = "ENABLED"
      # https://repost.aws/questions/QU-SweEQPqR2evZ-n_KaUL0A/ecs-understanding-of-capacityproviderreservation
      target_capacity        = 100
      instance_warmup_period = 300
    }
  }
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
    value = "enabled"
  }
}

resource "aws_ecs_task_definition" "ecs" {
  family = var.service_name
  container_definitions = jsonencode(
    [
      {
        name      = var.service_name
        image     = var.docker_image
        cpu       = 200
        memory    = 128
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
        environment = var.task_environment_variables
      }
    ]
  )
  execution_role_arn = aws_iam_role.ecs_task_execution_role.arn
  #  task_role_arn      = var.task_role_arn
}

resource "aws_ecs_service" "ecs" {
  name            = var.service_name
  cluster         = aws_ecs_cluster.ecs.id
  task_definition = aws_ecs_task_definition.ecs.arn
  desired_count   = var.task_desired_count
  lifecycle {
    ignore_changes = [desired_count]
  }
  #    iam_role        = aws_iam_role.task_role.arn

  load_balancer {
    target_group_arn = module.pod.target_group_arn
    container_name   = var.service_name
    container_port   = var.container_port
  }
  depends_on = [
    aws_iam_role.ecs_task_execution_role,
  ]
}
