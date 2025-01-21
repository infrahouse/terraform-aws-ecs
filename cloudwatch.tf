resource "aws_cloudwatch_log_group" "ecs" {
  count             = var.enable_cloudwatch_logs ? 1 : 0
  name              = local.cloudwatch_group
  retention_in_days = var.cloudwatch_log_group_retention
  tags = merge(
    local.default_module_tags,
    {
      VantaContainsUserData : false
      VantaContainsEPHI : false
    }
  )
}

resource "aws_cloudwatch_log_group" "ecs_ec2_syslog" {
  count             = var.enable_cloudwatch_logs ? 1 : 0
  name              = "${local.cloudwatch_group}-syslog"
  retention_in_days = var.cloudwatch_log_group_retention
  tags = merge(
    local.default_module_tags,
    {
      VantaContainsUserData : false
      VantaContainsEPHI : false
    }
  )
}

resource "aws_cloudwatch_log_group" "ecs_ec2_dmesg" {
  count             = var.enable_cloudwatch_logs ? 1 : 0
  name              = "${local.cloudwatch_group}-dmesg"
  retention_in_days = var.cloudwatch_log_group_retention
  tags = merge(
    local.default_module_tags,
    {
      VantaContainsUserData : false
      VantaContainsEPHI : false
    }
  )
}
