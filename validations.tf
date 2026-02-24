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

# Cross-variable validation: container_memory_reservation must be <= container_memory
check "memory_reservation_within_limit" {
  assert {
    condition = (
      var.container_memory_reservation == null ? true : var.container_memory_reservation <= var.container_memory
    )
    error_message = <<-EOF
      ╔════════════════════════════════════════════════════════════════════════╗
      ║                    ⚠️  CONFIGURATION ERROR ⚠️                          ║
      ╚════════════════════════════════════════════════════════════════════════╝

      Memory reservation must be less than or equal to the hard memory limit.

      Current configuration:
        - Hard memory limit (container_memory):             ${var.container_memory} MB
        - Soft memory limit (container_memory_reservation): ${coalesce(var.container_memory_reservation, "(not set)")} MB

      Problem:
        ECS requires that the memory reservation (soft limit) cannot exceed the
        hard memory limit. The container can use memory up to the hard limit, but
        ECS uses the reservation for task placement decisions.

      Solution:
        Adjust your configuration so that container_memory_reservation <= container_memory:

        # Good configurations:
        container_memory             = 512
        container_memory_reservation = 256  # Reserve 256MB, can burst to 512MB

        container_memory             = 1024
        container_memory_reservation = 512  # Reserve 512MB, can burst to 1024MB

        container_memory             = 128
        container_memory_reservation = null # No reservation (uses hard limit for scheduling)

      How memory limits work:
        - Reservation (soft): Used by ECS for task placement (bin packing)
        - Hard limit: Container is killed if it exceeds this limit
        - Burst capacity: container_memory - container_memory_reservation

      ════════════════════════════════════════════════════════════════════════
    EOF
  }
}

# Validate weighted routing configuration
check "weighted_routing_requires_set_identifier" {
  assert {
    condition     = var.dns_routing_policy == "simple" ? true : var.dns_set_identifier != null
    error_message = <<-EOF
      ╔════════════════════════════════════════════════════════════════════════╗
      ║                  ⚠️  CONFIGURATION ERROR ⚠️                            ║
      ╚════════════════════════════════════════════════════════════════════════╝

      When using dns_routing_policy = "weighted", you must also set dns_set_identifier.

      Current configuration:
        - dns_routing_policy: ${var.dns_routing_policy}
        - dns_set_identifier: ${var.dns_set_identifier == null ? "null (not set)" : var.dns_set_identifier}

      Problem:
        Route53 weighted routing records require a unique set_identifier to distinguish
        between multiple records with the same name.

      Solution:
        Add a unique dns_set_identifier to your configuration:

        dns_routing_policy = "weighted"
        dns_set_identifier = "my-service-v1"  # Must be unique per DNS record name
        dns_weight         = 100

      Naming conventions for dns_set_identifier:
        - "production-blue", "production-green" (blue/green deployments)
        - "v1", "v2", "v3" (version-based)
        - "website-pod", "ecs-service" (module-based)

      ════════════════════════════════════════════════════════════════════════
    EOF
  }
}

# Validate weighted routing is only supported for ALB
check "weighted_routing_alb_only" {
  assert {
    condition     = var.dns_routing_policy == "simple" ? true : var.lb_type == "alb"
    error_message = <<-EOF
      ╔════════════════════════════════════════════════════════════════════════╗
      ║                  ⚠️  CONFIGURATION ERROR ⚠️                            ║
      ╚════════════════════════════════════════════════════════════════════════╝

      Weighted routing is currently only supported for ALB (lb_type = "alb").

      Current configuration:
        - lb_type:            ${var.lb_type}
        - dns_routing_policy: ${var.dns_routing_policy}
        - dns_set_identifier: ${var.dns_set_identifier == null ? "null (not set)" : var.dns_set_identifier}

      Problem:
        The tcp-pod module (used for NLB) does not yet support weighted routing.
        This feature is only available when using an Application Load Balancer.

      Solution:
        Either:
        1. Use ALB instead of NLB:
           lb_type = "alb"

        2. Or use simple routing for NLB:
           dns_routing_policy = "simple"

      ════════════════════════════════════════════════════════════════════════
    EOF
  }
}

# Validate extra_target_groups is only used with ALB
check "extra_target_groups_alb_only" {
  assert {
    condition = (
      length(var.extra_target_groups) == 0 ? true : var.lb_type == "alb"
    )
    error_message = <<-EOF
      extra_target_groups is only supported with lb_type = "alb".

      Current configuration:
        - lb_type:              ${var.lb_type}
        - extra_target_groups:  ${length(var.extra_target_groups)} entries

      Solution:
        Either use lb_type = "alb" or remove extra_target_groups.
    EOF
  }
}

# Cross-variable validation: autoscaling_target must be appropriate for the metric type
locals {
  is_percentage_metric = contains([
    "ECSServiceAverageCPUUtilization",
    "ECSServiceAverageMemoryUtilization"
  ], var.autoscaling_metric)

  autoscaling_problem_message = local.is_percentage_metric ? (
    "CPU and Memory utilization metrics require a percentage value between 1-100."
    ) : (
    "ALBRequestCountPerTarget metric requires a positive number (requests per target)."
  )

  autoscaling_solution_message = local.is_percentage_metric ? (
    <<-EOT
    Set autoscaling_target to a percentage between 1-100:

        # Good configurations:
        autoscaling_metric = "${var.autoscaling_metric}"
        autoscaling_target = 70  # Scale to maintain 70% utilization

        autoscaling_metric = "${var.autoscaling_metric}"
        autoscaling_target = 80  # Scale to maintain 80% utilization
    EOT
    ) : (
    <<-EOT
    Set autoscaling_target to a positive number:

        # Good configurations:
        autoscaling_metric = "ALBRequestCountPerTarget"
        autoscaling_target = 100  # 100 requests per target

        autoscaling_metric = "ALBRequestCountPerTarget"
        autoscaling_target = 1000  # 1000 requests per target
    EOT
  )

  autoscaling_examples_message = local.is_percentage_metric ? (
    <<-EOT
    - Light workloads:   autoscaling_target = 50
        - Normal workloads:  autoscaling_target = 70
        - Heavy workloads:   autoscaling_target = 85
    EOT
    ) : (
    <<-EOT
    - Low traffic:    autoscaling_target = 50
        - Medium traffic: autoscaling_target = 100
        - High traffic:   autoscaling_target = 1000
    EOT
  )
}

check "autoscaling_target_valid_for_metric" {
  assert {
    condition = (
      # For percentage-based metrics (CPU and Memory), target must be 1-100
      local.is_percentage_metric ? (
        var.autoscaling_target == null ? true : (
          var.autoscaling_target >= 1 && var.autoscaling_target <= 100
        )
        ) : (
        # For ALBRequestCountPerTarget, target must be positive
        var.autoscaling_metric == "ALBRequestCountPerTarget" ? (
          var.autoscaling_target != null && var.autoscaling_target > 0
        ) : true
      )
    )
    error_message = <<-EOF
      ╔════════════════════════════════════════════════════════════════════════╗
      ║                    ⚠️  CONFIGURATION ERROR ⚠️                          ║
      ╚════════════════════════════════════════════════════════════════════════╝

      Autoscaling target value is invalid for the selected metric type.

      Current configuration:
        - Autoscaling metric: ${var.autoscaling_metric}
        - Autoscaling target: ${coalesce(var.autoscaling_target, "(not set)")}

      Problem:
        ${local.autoscaling_problem_message}

      Solution:
        ${local.autoscaling_solution_message}

      Common configurations:
        ${local.autoscaling_examples_message}

      ════════════════════════════════════════════════════════════════════════
    EOF
  }
}
