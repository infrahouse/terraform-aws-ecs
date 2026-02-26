data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

data "aws_subnet" "selected" {
  id = var.asg_subnets[0]
}

data "aws_subnet" "load_balancer" {
  id = var.load_balancer_subnets[0]
}

# Auto-discover Internet Gateway attached to the VPC
# Notes:
# - AWS allows exactly ONE Internet Gateway per VPC
# - The IGW is discovered in the same AWS account/region as the provider
# - If no IGW is found, the vpc_has_internet_gateway check will fail with a helpful error
data "aws_internet_gateway" "default" {
  filter {
    name   = "attachment.vpc-id"
    values = [data.aws_subnet.load_balancer.vpc_id]
  }
}

# Get IAM role name from instance profile (for tcp-pod which only returns instance_profile_name)
data "aws_iam_instance_profile" "tcp_pod" {
  count = var.lb_type == "nlb" ? 1 : 0
  name  = var.lb_type == "nlb" ? module.tcp-pod[0].instance_profile_name : null
}

data "aws_ami" "ecs" {
  most_recent = true

  filter {
    name   = "name"
    values = ["al2023-ami-ecs-hvm-*"]
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
                var.enable_cloudwatch_logs == true ? [
                  {
                    path : local.cloudwatch_agent_config_path
                    permissions : "0644"
                    content : templatefile(
                      "${path.module}/assets/cloudwatch_agent_config.tftmpl",
                      {
                        syslog_group_name : aws_cloudwatch_log_group.ecs_ec2_syslog[0].name
                        dmesg_group_name : aws_cloudwatch_log_group.ecs_ec2_dmesg[0].name
                      }
                    )
                  }
                ] : [],
                var.enable_vector_agent == true ? [
                  {
                    path : local.vector_agent_config_path
                    permissions : "0644"
                    content : var.vector_agent_config != null ? var.vector_agent_config : templatefile(
                      "${path.module}/assets/vector_agent_config.yaml.tftmpl",
                      {
                        environment                = var.environment
                        aws_region                 = data.aws_region.current.name
                        vector_aggregator_endpoint = var.vector_aggregator_endpoint
                      }
                    )
                  }
                ] : [],
                var.extra_files
              )
            },
            {
              "runcmd" : concat([
                "fallocate -l ${data.aws_ec2_instance_type.ecs.memory_size * 2}M /swapfile",
                "chmod 600 /swapfile",
                "mkswap /swapfile",
                "swapon /swapfile"
              ], var.cloudinit_extra_commands)
            }
          )

        )
      ]
    )
  }
}

data "aws_iam_policy_document" "instance_policy" {
  source_policy_documents = var.extra_instance_profile_permissions != null ? [var.extra_instance_profile_permissions] : []

  # Note: ECS instance permissions (ecs:*, ec2:Describe*) are now provided by
  # AWS managed policy AmazonEC2ContainerServiceforEC2Role attached in iam.tf
  # This inline policy only contains module-specific permissions

  dynamic "statement" {
    for_each = var.enable_cloudwatch_logs ? [1] : []
    content {
      actions = [
        "logs:CreateLogStream",
        "logs:PutLogEvents",
      ]
      resources = [format("%s:*", aws_cloudwatch_log_group.ecs[0].arn)]
    }
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

data "aws_iam_policy_document" "ecs_cloudwatch_logs_policy" {
  count = var.enable_cloudwatch_logs ? 1 : 0
  statement {
    sid = "AllowDescribeLogGroups"
    actions = [
      "logs:DescribeLogGroups",
    ]
    resources = ["*"]
  }

  statement {
    sid = "AllowECSExecLogging"
    actions = [
      "logs:CreateLogStream",
      "logs:DescribeLogStreams",
      "logs:PutLogEvents",
    ]
    resources = ["${aws_cloudwatch_log_group.ecs[0].arn}:*"]
  }

}

data "aws_route53_zone" "this" {
  zone_id  = var.zone_id
  provider = aws.dns
}

data "aws_ec2_instance_type" "backend" {
  instance_type = var.asg_instance_type
}
