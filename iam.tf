resource "aws_iam_role" "ecs_task_execution_role" {
  name               = "${var.service_name}TaskExecutionRole"
  assume_role_policy = data.aws_iam_policy_document.assume_role_policy.json
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_role_policy" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = data.aws_iam_policy.ecs-task-execution-role-policy.arn
}
