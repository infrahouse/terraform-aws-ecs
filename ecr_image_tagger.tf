module "ecr_image_tagger" {
  count   = var.enable_ecr_image_tagging ? 1 : 0
  source  = "registry.infrahouse.com/infrahouse/lambda-monitored/aws"
  version = "1.0.4"

  function_name     = "${var.service_name}-ecr-image-tagger"
  description       = "Tags deployed ECR images for lifecycle retention"
  handler           = "main.lambda_handler"
  lambda_source_dir = "${path.module}/assets/ecr_image_tagger"
  timeout           = 120
  memory_size       = var.ecr_image_tagger_memory_size

  environment_variables = {
    ECS_CLUSTER_NAME    = aws_ecs_cluster.ecs.name
    ECS_SERVICE_NAME    = aws_ecs_service.ecs.name
    DEPLOYED_TAG_PREFIX = var.deployed_image_tag_prefix
    LOG_LEVEL           = var.ecr_image_tagger_log_level
  }

  additional_iam_policy_arns = [
    aws_iam_policy.ecr_image_tagger[0].arn
  ]

  alarm_emails = var.alarm_emails
  tags         = local.default_module_tags
}

# IAM policy for ECS/ECR access

data "aws_iam_policy_document" "ecr_image_tagger" {
  count = var.enable_ecr_image_tagging ? 1 : 0
  statement {
    sid = "DescribeECSServices"
    actions = [
      "ecs:DescribeServices",
    ]
    resources = [
      join(":", [
        "arn:aws:ecs",
        data.aws_region.current.name,
        data.aws_caller_identity.current.account_id,
        "service/${aws_ecs_cluster.ecs.name}/*"
      ])
    ]
  }

  statement {
    sid = "DescribeTaskDefinition"
    actions = [
      "ecs:DescribeTaskDefinition",
    ]
    resources = ["*"]
  }

  statement {
    sid = "ECRReadImages"
    actions = [
      "ecr:BatchGetImage",
      "ecr:DescribeImages",
    ]
    resources = [
      "arn:aws:ecr:*:${data.aws_caller_identity.current.account_id}:repository/*"
    ]
  }

  # ecr:PutImage is scoped to only the repository from var.docker_image
  # to follow least privilege. Read permissions remain broad since the
  # Lambda may need to inspect sidecar images from other repos.
  statement {
    sid = "ECRTagImages"
    actions = [
      "ecr:PutImage",
    ]
    resources = [
      local.ecr_image_repo_arn
    ]
  }
}

resource "aws_iam_policy" "ecr_image_tagger" {
  count       = var.enable_ecr_image_tagging ? 1 : 0
  name_prefix = substr("${var.service_name}-ecr-tagger-", 0, 38)
  policy      = data.aws_iam_policy_document.ecr_image_tagger[0].json
  tags = merge(
    local.default_module_tags,
    {
      VantaContainsUserData : false
      VantaContainsEPHI : false
    }
  )
}

# EventBridge rule to match SERVICE_STEADY_STATE for this specific service.
# Filters on the service ARN in the "resources" field to avoid triggering
# on other services in the same cluster (e.g., cloudwatch-agent-daemon).

resource "aws_cloudwatch_event_rule" "ecr_image_tagger" {
  count       = var.enable_ecr_image_tagging ? 1 : 0
  name_prefix = substr("${var.service_name}-ecr-tag-", 0, 38)
  description = "Triggers ECR image tagging when ${var.service_name} reaches steady state"

  event_pattern = jsonencode({
    "detail-type" = ["ECS Service Action"]
    "source"      = ["aws.ecs"]
    "resources"   = [aws_ecs_service.ecs.id]
    "detail" = {
      "eventType"  = ["INFO"]
      "eventName"  = ["SERVICE_STEADY_STATE"]
      "clusterArn" = [aws_ecs_cluster.ecs.arn]
    }
  })

  tags = merge(
    local.default_module_tags,
    {
      VantaContainsUserData : false
      VantaContainsEPHI : false
    }
  )
}

resource "aws_cloudwatch_event_target" "ecr_image_tagger" {
  count = var.enable_ecr_image_tagging ? 1 : 0
  rule  = aws_cloudwatch_event_rule.ecr_image_tagger[0].name
  arn   = module.ecr_image_tagger[0].lambda_function_arn
}

resource "aws_lambda_permission" "ecr_image_tagger" {
  count         = var.enable_ecr_image_tagging ? 1 : 0
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = module.ecr_image_tagger[0].lambda_function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.ecr_image_tagger[0].arn
}
