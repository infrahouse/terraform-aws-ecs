resource "aws_cloudwatch_event_rule" "failed_deployment_event_rule" {
  count       = var.enable_deployment_circuit_breaker && var.sns_topic_arn != null ? 1 : 0
  name        = format("%s-deployment-failure", aws_ecs_service.ecs.name)
  description = "Task deployment failed"
  event_pattern = jsonencode({
    detail-type = ["ECS Deployment State Change"]
    source      = ["aws.ecs"]
    resources   = [aws_ecs_service.ecs.id]
    detail = {
      eventType = ["ERROR"]
      eventName = ["SERVICE_DEPLOYMENT_FAILED"]
    }
  })
}

resource "aws_cloudwatch_event_target" "ecs_task_deployment_failure_sns" {
  count     = var.enable_deployment_circuit_breaker && var.sns_topic_arn != null ? 1 : 0
  rule      = aws_cloudwatch_event_rule.failed_deployment_event_rule[0].name
  target_id = "SendToSNS"
  arn       = var.sns_topic_arn
}

