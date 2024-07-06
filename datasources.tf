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


data "aws_ami" "ubuntu_22" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-*"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["099720109477"] # Canonical
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
          }
        )
      ]
    )
  }
}

module "userdata" {
  source                   = "registry.infrahouse.com/infrahouse/cloud-init/aws"
  version                  = "1.12.4"
  environment              = var.environment
  role                     = "ecsnode"
  puppet_debug_logging     = var.puppet_debug_logging
  puppet_environmentpath   = var.puppet_environmentpath
  puppet_hiera_config_path = var.puppet_hiera_config_path
  puppet_module_path       = var.puppet_module_path
  puppet_root_directory    = var.puppet_root_directory
  puppet_manifest          = var.puppet_manifest
  packages = concat(
    var.packages,
    [
      "awscli",
      "nfs-common"
    ]
  )
  extra_files = var.extra_files
  extra_repos = var.extra_repos

  custom_facts = merge(
    {
      ecs: {
        cluster: var.service_name
        loglevel: var.ecs_loglevel
      }
    },
    var.puppet_custom_facts,
      var.smtp_credentials_secret != null ? {
      postfix : {
        smtp_credentials : var.smtp_credentials_secret
      }
    } : {}
  )
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
