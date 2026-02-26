data "aws_iam_policy_document" "task_role_assume" {
  statement {
    principals {
      identifiers = [
        "ecs-tasks.amazonaws.com"
      ]
      type = "Service"
    }
    actions = [
      "sts:AssumeRole"
    ]
    condition {
      test = "StringEquals"
      values = [
        data.aws_caller_identity.this.account_id
      ]
      variable = "aws:SourceAccount"
    }
    condition {
      test = "ArnLike"
      values = [
        "arn:aws:ecs:${data.aws_region.current.name}:${data.aws_caller_identity.this.account_id}:*"
      ]
      variable = "aws:SourceArn"
    }
  }
}

data "aws_iam_policy_document" "task_role_permissions" {
  statement {
    actions = [
      "s3:*"
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "task_role" {
  name_prefix = "task-"
  policy      = data.aws_iam_policy_document.task_role_permissions.json
}

resource "aws_iam_role" "task_role" {
  name_prefix        = "task-"
  assume_role_policy = data.aws_iam_policy_document.task_role_assume.json
}

resource "aws_iam_role_policy_attachment" "task_role" {
  policy_arn = aws_iam_policy.task_role.arn
  role       = aws_iam_role.task_role.name
}
