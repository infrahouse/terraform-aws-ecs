# Vector Agent Daemon: log/metrics collection from ECS hosts.
# Mirrors the CloudWatch agent daemon pattern (cloudwatch_agent.tf).
# Collects container logs + host metrics, forwards to Vector Aggregator.
# Config written to host via cloud-init, mounted into daemon container.

resource "aws_iam_role" "vector_agent_task_role" {
  count              = var.enable_vector_agent ? 1 : 0
  name_prefix        = format("%s-vec-task-", var.service_name)
  assume_role_policy = data.aws_iam_policy_document.cloudwatch_agent_task_role_assume_policy.json
  tags = merge(
    local.default_module_tags,
    {
      VantaContainsUserData : false
      VantaContainsEPHI : false
    }
  )
}

resource "aws_iam_role" "vector_agent_execution_role" {
  count              = var.enable_vector_agent ? 1 : 0
  name_prefix        = format("%s-vec-exec-", var.service_name)
  assume_role_policy = data.aws_iam_policy_document.cloudwatch_agent_task_role_assume_policy.json
  tags = merge(
    local.default_module_tags,
    {
      VantaContainsUserData : false
      VantaContainsEPHI : false
    }
  )
}

resource "aws_iam_role_policy_attachment" "vector_agent_execution_policy" {
  count      = var.enable_vector_agent ? 1 : 0
  role       = aws_iam_role.vector_agent_execution_role[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy_attachment" "vector_agent_task_policy" {
  for_each   = var.enable_vector_agent ? toset(var.vector_agent_task_policy_arns) : toset([])
  role       = aws_iam_role.vector_agent_task_role[0].name
  policy_arn = each.value
}

resource "aws_ecs_task_definition" "vector_agent" {
  count              = var.enable_vector_agent ? 1 : 0
  family             = format("%s-vector-agent-daemon", var.service_name)
  task_role_arn      = aws_iam_role.vector_agent_task_role[0].arn
  execution_role_arn = aws_iam_role.vector_agent_execution_role[0].arn

  container_definitions = jsonencode(
    [
      {
        name      = "vector-agent"
        image     = var.vector_agent_image
        memory    = local.vector_agent_container_resources.memory
        cpu       = local.vector_agent_container_resources.cpu
        essential = true
        command   = ["--config", "/etc/vector/vector.yaml"]
        mountPoints = [
          {
            sourceVolume  = "docker-containers"
            containerPath = "/var/lib/docker/containers"
            readOnly      = true
          },
          {
            sourceVolume  = "docker-sock"
            containerPath = "/var/run/docker.sock"
            readOnly      = true
          },
          {
            sourceVolume  = "vector-config"
            containerPath = "/etc/vector/vector.yaml"
            readOnly      = true
          }
        ]
        healthCheck = {
          command     = ["CMD-SHELL", "wget -qO- http://localhost:8686/health || exit 1"]
          interval    = 30
          timeout     = 5
          retries     = 3
          startPeriod = 60
        }
      }
    ]
  )

  volume {
    name      = "docker-containers"
    host_path = "/var/lib/docker/containers"
  }

  # Docker socket grants Docker API access (read-only). Required by
  # Vector's docker_logs source to discover and tail container logs.
  # Unlike the CloudWatch agent (which reads /var/log), Vector needs
  # the socket for container metadata and log streaming.
  volume {
    name      = "docker-sock"
    host_path = "/var/run/docker.sock"
  }

  volume {
    name      = "vector-config"
    host_path = local.vector_agent_config_path
  }

  tags = merge(
    local.default_module_tags,
    {
      VantaContainsUserData : false
      VantaContainsEPHI : false
    }
  )
}

resource "aws_ecs_service" "vector_agent" {
  count               = var.enable_vector_agent ? 1 : 0
  name                = "vector-agent-daemon"
  cluster             = aws_ecs_cluster.ecs.id
  task_definition     = aws_ecs_task_definition.vector_agent[0].arn
  launch_type         = "EC2"
  scheduling_strategy = "DAEMON"
  tags = merge(
    local.default_module_tags,
    {
      VantaContainsUserData : false
      VantaContainsEPHI : false
    }
  )
}
