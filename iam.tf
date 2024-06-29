resource "aws_iam_role" "ecs_task_execution_role" {
  # expected length of name_prefix to be in the range (1 - 38)
  name_prefix        = substr("${var.service_name}TaskExecutionRole", 0, 38)
  assume_role_policy = data.aws_iam_policy_document.assume_role_policy.json
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_role_policy" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = data.aws_iam_policy.ecs-task-execution-role-policy.arn
}
