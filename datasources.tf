data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

data "aws_subnet" "selected" {
  id = var.asg_subnets[0]
}

data "aws_subnet" "load_balancer" {
  id = var.load_balancer_subnets[0]
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

# GPU-optimized ECS AMI. Selected automatically when gpu_count > 0 and the caller
# did not pin ami_id (see local.selected_ami). The standard data.aws_ami.ecs above
# has no NVIDIA drivers, so a GPU reservation would never place on it. Read only
# when actually needed.
data "aws_ssm_parameter" "ecs_gpu_ami" {
  count = var.ami_id == null && var.gpu_count > 0 ? 1 : 0
  name  = "/aws/service/ecs/optimized-ami/amazon-linux-2023/gpu/recommended/image_id"
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
                        "ECS_LOGLEVEL=${var.ecs_log_level}",
                        "ECS_ALLOW_OFFHOST_INTROSPECTION_ACCESS=true"
                      ]
                    )
                  }
                ],
                # The containerized cloudwatch-agent daemon is logs-only. GPU metrics are
                # NOT collected here: a container without a GPU resourceRequirements
                # reservation cannot see nvidia-smi/NVML on the AL2023 GPU AMI (GPU
                # injection is gated through ECS's own assignment path). GPU metrics are
                # instead collected by a host-level CloudWatch agent (see the write_files
                # and runcmd blocks gated on gpu_count > 0 below), which has native
                # nvidia-smi access.
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
                # Host-level CloudWatch agent config for GPU metrics. The host has native
                # nvidia-smi, so its nvidia_gpu collector publishes nvidia_smi_utilization_gpu
                # (and memory) into the same CWAgent namespace, aggregated by
                # AutoScalingGroupName — the exact series the GPU scaling policy and dashboard
                # consume. Installed and started by the runcmd below. $${aws:...} is a literal
                # the agent resolves at runtime.
                var.gpu_count > 0 ? [
                  {
                    path : local.gpu_host_agent_config_path
                    permissions : "0644"
                    content : jsonencode({
                      agent = { run_as_user = "root" }
                      metrics = {
                        namespace              = local.gpu_metrics_namespace
                        append_dimensions      = { AutoScalingGroupName = "$${aws:AutoScalingGroupName}" }
                        aggregation_dimensions = [["AutoScalingGroupName"]]
                        metrics_collected = {
                          nvidia_gpu = {
                            measurement                 = ["utilization_gpu", "memory_used", "memory_total"]
                            metrics_collection_interval = 60
                          }
                        }
                      }
                    })
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
                        service_name               = var.service_name
                        exclude_containers         = concat(["vector-agent"], var.vector_agent_exclude_containers)
                      }
                    )
                  }
                ] : [],
                var.extra_files
              )
            },
            {
              "runcmd" : concat(
                [
                  "fallocate -l ${data.aws_ec2_instance_type.ecs.memory_size * 2}M /swapfile",
                  "chmod 600 /swapfile",
                  "mkswap /swapfile",
                  "swapon /swapfile"
                ],
                # Install and start the host-level CloudWatch agent for GPU metrics.
                # It runs as a systemd service (independent of docker/ecs) and reads the
                # host's GPUs via native nvidia-smi. dnf install is a no-op if the agent is
                # already present on the AMI.
                #
                # Tradeoff: this host agent is intentionally left UNPINNED (dnf pulls the
                # latest amazon-cloudwatch-agent from the AL2023 repo / AMI), unlike the
                # containerized logs agent which is pinned via var.cloudwatch_agent_image.
                # It's stock AWS tooling and the AMI already floats, so pinning here buys
                # little and a pinned RPM version can disappear from the repo. The cost is a
                # small reproducibility gap: a re-launch may pull a different agent build.
                var.gpu_count > 0 ? [
                  "dnf install -y amazon-cloudwatch-agent",
                  "/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -s -c file:${local.gpu_host_agent_config_path}"
                ] : [],
                var.cloudinit_extra_commands
              )
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

  # The host-level CloudWatch agent (GPU metrics) publishes with the instance role.
  # PutMetricData has no resource-level scoping, so restrict it to the GPU namespace.
  dynamic "statement" {
    for_each = var.gpu_count > 0 ? [1] : []
    content {
      sid       = "AllowGpuMetricPublish"
      actions   = ["cloudwatch:PutMetricData"]
      resources = ["*"]
      condition {
        test     = "StringEquals"
        variable = "cloudwatch:namespace"
        values   = [local.gpu_metrics_namespace]
      }
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
