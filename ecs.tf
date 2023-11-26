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
        cpu       = 10
        memory    = 256
        essential = true
        portMappings = [
          {
            containerPort = var.container_port
            hostPort      = var.container_port
          }
        ]
      },
    ]
  )
  execution_role_arn = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn      = var.task_role_arn
}

resource "aws_iam_role" "ecs_task_execution_role" {
  name               = "${var.service_name}TaskExecutionRole"
  assume_role_policy = data.aws_iam_policy_document.assume_role_policy.json
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_role_policy" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = data.aws_iam_policy.ecs-task-execution-role-policy.arn
}

resource "aws_ecs_service" "ecs" {
  name            = var.service_name
  cluster         = aws_ecs_cluster.ecs.id
  task_definition = aws_ecs_task_definition.ecs.arn
  desired_count   = var.container_desired_count
  #  iam_role        = aws_iam_role.task_role.arn

  ordered_placement_strategy {
    type  = "binpack"
    field = "cpu"
  }

  load_balancer {
    target_group_arn = module.pod.target_group_arn
    container_name   = var.service_name
    container_port   = var.container_port
  }
}
