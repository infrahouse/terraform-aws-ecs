data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

data "aws_subnet" "selected" {
  id = var.asg_subnets[0]
}

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
          merge(
            var.users == null ? {} : {
              users : var.users
            },
            {
              write_files : concat(
                [
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
                ],
                var.extra_files
              )
            },
            {
              "runcmd" : [
                "fallocate -l ${data.aws_ec2_instance_type.ecs.memory_size * 2}M /swapfile",
                "chmod 600 /swapfile",
                "mkswap /swapfile",
                "swapon /swapfile"
              ]
            }
          )

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

data "aws_ec2_instance_type" "ecs" {
  instance_type = var.asg_instance_type
}
