resource "aws_iam_role" "cloudwatch_agent_task_role" {
  count       = var.enable_cloudwatch_agent ? 1 : 0
  name_prefix = format("%s-cw-agent-", var.service_name)
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })
  tags = local.default_module_tags
}

resource "aws_iam_role_policy_attachment" "cloudwatch_policy_attachment" {
  count      = var.enable_cloudwatch_agent ? 1 : 0
  role       = aws_iam_role.cloudwatch_agent_task_role[0].name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_policy" {
  count      = var.enable_cloudwatch_agent ? 1 : 0
  role       = aws_iam_role.cloudwatch_agent_task_role[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_ecs_task_definition" "cloudwatch_agent" {
  count              = var.enable_cloudwatch_agent ? 1 : 0
  family             = "cloudwatch-agent-daemon"
  task_role_arn      = aws_iam_role.cloudwatch_agent_task_role[0].arn
  execution_role_arn = aws_iam_role.cloudwatch_agent_task_role[0].arn

  container_definitions = jsonencode([{
    name      = "cloudwatch-agent"
    image     = var.cloudwatch_agent_image
    memory    = var.cloudwatch_agent_container_resources.memory
    cpu       = var.cloudwatch_agent_container_resources.cpu
    essential = true
    mountPoints = [{
      sourceVolume  = "log-volume"
      containerPath = "/var/log"
      },
      {
        sourceVolume  = "config-volume"
        containerPath = "/etc/cwagentconfig"
        readOnly      = true
      }
    ]
  }])

  volume {
    name      = "log-volume"
    host_path = "/var/log"
  }

  volume {
    name      = "config-volume"
    host_path = var.cloudwatch_agent_config_path
  }
  tags = local.default_module_tags
}

resource "aws_ecs_service" "cloudwatch_agent_service" {
  count               = var.enable_cloudwatch_agent ? 1 : 0
  name                = "cloudwatch-agent-daemon"
  cluster             = aws_ecs_cluster.ecs.id
  task_definition     = aws_ecs_task_definition.cloudwatch_agent[0].arn
  launch_type         = "EC2"
  scheduling_strategy = "DAEMON"
  tags                = local.default_module_tags
}
