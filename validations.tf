# validations.tf
#
# This file contains cross-variable validation checks using Terraform check blocks.
# These checks will display errors during terraform plan when invalid configurations
# are detected, but provide better error messages than native validation blocks.

# Cross-variable validation: healthcheck interval must be >= timeout
check "healthcheck_interval_greater_than_timeout" {
  assert {
    condition     = var.healthcheck_interval >= var.healthcheck_timeout
    error_message = <<-EOF
      ╔════════════════════════════════════════════════════════════════════════╗
      ║                    ⚠️  CONFIGURATION ERROR ⚠️                          ║
      ╚════════════════════════════════════════════════════════════════════════╝

      Health check interval must be greater than or equal to health check timeout.

      Current configuration:
        - Health check timeout:  ${var.healthcheck_timeout} seconds
        - Health check interval: ${var.healthcheck_interval} seconds

      Problem:
        AWS requires that the interval value is greater than or equal to the timeout value.
        The health check needs enough time to complete before the next check starts.

      Solution:
        Adjust your configuration so that interval >= timeout. For example:

        # Good configuration:
        healthcheck_timeout  = 5   # Time to wait for response
        healthcheck_interval = 10  # Time between checks (default)

      Common configurations:
        - Fast checks:    timeout = 2,  interval = 5
        - Normal checks:  timeout = 5,  interval = 10  (default)
        - Slow checks:    timeout = 10, interval = 30

      ════════════════════════════════════════════════════════════════════════
    EOF
  }
}

# Cross-region validation: KMS key must be in the same region as CloudWatch log groups
check "kms_key_region_match" {
  assert {
    condition = (
      var.cloudwatch_log_kms_key_id == null ||
      can(regex("arn:aws:kms:${data.aws_region.current.name}:", var.cloudwatch_log_kms_key_id))
    )
    error_message = <<-EOF
      ╔════════════════════════════════════════════════════════════════════════╗
      ║                    ⚠️  CONFIGURATION ERROR ⚠️                          ║
      ╚════════════════════════════════════════════════════════════════════════╝

      KMS key must be in the same AWS region as the CloudWatch log groups.

      Current configuration:
        - CloudWatch logs region: ${data.aws_region.current.name}
        - KMS key ARN:            ${coalesce(var.cloudwatch_log_kms_key_id, "(not provided)")}

      Problem:
        AWS KMS keys are regional resources. CloudWatch Logs can only use KMS keys
        from the same region where the log groups are created.

      Solution:
        Create your KMS key in the ${data.aws_region.current.name} region:

        resource "aws_kms_key" "cloudwatch_logs" {
          provider    = aws  # Ensure this provider targets ${data.aws_region.current.name}
          description = "KMS key for CloudWatch Logs encryption"
          # ... other configuration
        }

        Then reference it in your module:

        module "ecs_service" {
          cloudwatch_log_kms_key_id = aws_kms_key.cloudwatch_logs.arn
          # ... other configuration
        }

      Note:
        If you need to deploy ECS services in multiple regions, you must create
        separate KMS keys in each region.

      ════════════════════════════════════════════════════════════════════════
    EOF
  }
}

# Cross-variable validation: task_max_count must be >= task_min_count
check "task_count_range" {
  assert {
    condition     = var.task_max_count >= var.task_min_count
    error_message = <<-EOF
      ╔════════════════════════════════════════════════════════════════════════╗
      ║                    ⚠️  CONFIGURATION ERROR ⚠️                          ║
      ╚════════════════════════════════════════════════════════════════════════╝

      Maximum task count must be greater than or equal to minimum task count.

      Current configuration:
        - Minimum task count: ${var.task_min_count}
        - Maximum task count: ${var.task_max_count}

      Problem:
        ECS autoscaling cannot function properly if the maximum task count is less
        than the minimum task count. The service needs the flexibility to scale
        between the minimum and maximum values.

      Solution:
        Adjust your configuration so that task_max_count >= task_min_count:

        # Good configurations:
        task_min_count = 1
        task_max_count = 10  # Can scale from 1 to 10 tasks

        task_min_count = 2
        task_max_count = 2   # Fixed at 2 tasks (no autoscaling)

        task_min_count = 5
        task_max_count = 20  # Can scale from 5 to 20 tasks

      Common configurations:
        - Small services:    min = 1,  max = 5
        - Medium services:   min = 2,  max = 10
        - Large services:    min = 5,  max = 50
        - No autoscaling:    min = max (e.g., both set to 3)

      ════════════════════════════════════════════════════════════════════════
    EOF
  }
}

# Validation: VPC must have an Internet Gateway attached
check "vpc_has_internet_gateway" {
  assert {
    condition     = data.aws_internet_gateway.default.id != null && data.aws_internet_gateway.default.id != ""
    error_message = <<-EOF
      ╔════════════════════════════════════════════════════════════════════════╗
      ║                    ⚠️  CONFIGURATION ERROR ⚠️                          ║
      ╚════════════════════════════════════════════════════════════════════════╝

      No Internet Gateway found attached to the VPC.

      Current configuration:
        - VPC ID: ${data.aws_subnet.load_balancer.vpc_id}
        - Load balancer subnets require internet access

      Problem:
        This module creates a public-facing load balancer that requires an Internet
        Gateway for inbound traffic. The VPC does not have an Internet Gateway attached.

      Solution:
        Create and attach an Internet Gateway to your VPC:

        resource "aws_internet_gateway" "main" {
          vpc_id = "${data.aws_subnet.load_balancer.vpc_id}"

          tags = {
            Name = "main-igw"
          }
        }

        # Ensure the IGW is attached before running this module
        module "ecs_service" {
          depends_on = [aws_internet_gateway.main]
          # ... your configuration
        }

      Note:
        - Each VPC can have exactly ONE Internet Gateway (AWS limitation)
        - For private VPCs without internet access, this module is not suitable
        - The Internet Gateway is auto-discovered from the VPC of your load balancer subnets

      ════════════════════════════════════════════════════════════════════════
    EOF
  }
}
