resource "aws_iam_role" "ecs_task_execution_role" {
  # expected length of name_prefix to be in the range (1 - 38)
  name_prefix        = substr("${var.service_name}TaskExecutionRole", 0, 38)
  assume_role_policy = data.aws_iam_policy_document.assume_role_policy.json
  tags = merge(
    local.default_module_tags,
    {
      VantaContainsUserData : false
      VantaContainsEPHI : false
    }
  )
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_role_policy" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = data.aws_iam_policy.ecs-task-execution-role-policy.arn
}

resource "aws_iam_policy" "ecs_task_execution_logs_policy" {
  count  = var.enable_cloudwatch_logs ? 1 : 0
  policy = data.aws_iam_policy_document.ecs_cloudwatch_logs_policy[0].json
  tags = merge(
    local.default_module_tags,
    {
      VantaContainsUserData : false
      VantaContainsEPHI : false
    }
  )
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_role_logs_policy" {
  count      = var.enable_cloudwatch_logs ? 1 : 0
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = aws_iam_policy.ecs_task_execution_logs_policy[0].arn
}

resource "aws_iam_role_policy_attachment" "extra_policy_attachment" {
  count      = var.execution_task_role_policy_arn != null ? 1 : 0
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = var.execution_task_role_policy_arn
}

resource "aws_iam_role_policy_attachment" "execution_extra_policy" {
  for_each   = var.execution_extra_policy
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = each.value
}
