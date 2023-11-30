data "aws_ami" "ecs" {
  most_recent = true

  filter {
    name   = "name"
    values = ["amzn2-ami-ecs-hvm-*"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["591542846629"] # Amazon
}


data "cloudinit_config" "ecs" {
  gzip          = false
  base64_encode = true

  part {
    content_type = "text/cloud-config"
    content = join(
      "\n",
      [
        "#cloud-config",
        yamlencode(
          {
            write_files : [
              {
                path : "/etc/ecs/ecs.config"
                permissions : "0644"
                content : join(
                  "\n",
                  [
                    "ECS_CLUSTER=${var.service_name}",
                    "ECS_LOGLEVEL=debug",
                    "ECS_ALLOW_OFFHOST_INTROSPECTION_ACCESS=true"
                  ]
                )
              }
            ]
          }
        )
      ]
    )
  }
}

data "aws_iam_policy_document" "instance_policy" {
  statement {
    actions   = ["ec2:Describe*"]
    resources = ["*"]
  }
  statement {
    actions   = ["ecs:*"]
    resources = ["*"]
  }
}

data "aws_iam_policy" "administrator-access" {
  name = "AdministratorAccess"
}

data "aws_iam_policy_document" "assume_role_policy" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

data "aws_iam_policy" "ecs-task-execution-role-policy" {
  name = "AmazonECSTaskExecutionRolePolicy"
}

data "aws_region" "current" {}

data "aws_caller_identity" "current" {}
