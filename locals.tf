check "asg_size_validation" {
  assert {
    condition = (
      var.asg_min_size == null || var.asg_max_size == null
      ? true
      : var.asg_max_size >= var.asg_min_size
    )
    error_message = "asg_max_size (${var.asg_max_size}) must be greater than or equal to asg_min_size (${var.asg_min_size}) when both are explicitly set."
  }
}

locals {
  module_version = "7.3.0"

  module_name = "infrahouse/ecs/aws"
  default_module_tags = merge(
    {
      environment : var.environment
      service : var.service_name
      account : data.aws_caller_identity.current.account_id
      created_by_module : local.module_name
    },
    var.upstream_module != null ? {
      upstream_module : var.upstream_module
    } : {},
    local.vanta_tags,
    var.tags
  )
  vanta_tags = merge(
    var.vanta_owner != null ? {
      VantaOwner : var.vanta_owner
    } : {},
    {
      VantaNonProd : !contains(var.vanta_production_environments, var.environment)
      VantaContainsUserData : var.vanta_contains_user_data
      VantaContainsEPHI : var.vanta_contains_ephi
    },
    var.vanta_description != null ? {
      VantaDescription : var.vanta_description
    } : {},
    var.vanta_user_data_stored != null ? {
      VantaUserDataStored : var.vanta_user_data_stored
    } : {},
    var.vanta_no_alert != null ? {
      VantaNoAlert : var.vanta_no_alert
    } : {}
  )

  cloudwatch_group = var.cloudwatch_log_group == null ? "/ecs/${var.environment}/${var.service_name}" : var.cloudwatch_log_group
  log_configuration = var.enable_cloudwatch_logs ? {
    logDriver = "awslogs"
    options = {
      "awslogs-group"  = aws_cloudwatch_log_group.ecs[0].name
      "awslogs-region" = data.aws_region.current.name
    }
  } : null
  asg_name                        = var.lb_type == "alb" ? module.pod[0].asg_name : module.tcp-pod[0].asg_name
  arg_arn                         = var.lb_type == "alb" ? module.pod[0].asg_arn : module.tcp-pod[0].asg_arn
  target_group_arn                = var.lb_type == "alb" ? module.pod[0].target_group_arn : module.tcp-pod[0].target_group_arn
  load_balancer_arn               = var.lb_type == "alb" ? module.pod[0].load_balancer_arn : module.tcp-pod[0].load_balancer_arn
  load_balancer_dns_name          = var.lb_type == "alb" ? module.pod[0].load_balancer_dns_name : module.tcp-pod[0].load_balancer_dns_name
  backend_security_group          = var.lb_type == "alb" ? module.pod[0].backend_security_group : module.tcp-pod[0].backend_security_group
  instance_role_name              = var.lb_type == "alb" ? module.pod[0].instance_role_name : data.aws_iam_instance_profile.tcp_pod[0].role_name
  instance_role_policy_name       = var.lb_type == "alb" ? module.pod[0].instance_role_policy_name : module.tcp-pod[0].instance_role_policy_name
  instance_role_policy_attachment = var.lb_type == "alb" ? module.pod[0].instance_role_policy_attachment : module.tcp-pod[0].instance_role_policy_attachment

  cloudwatch_agent_config_path = "/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json"
  cloudwatch_agent_container_resources = {
    cpu    = 128
    memory = 256
  }


  # ASG sizing: User-provided values take precedence over calculated defaults.
  # - asg_min_size defaults to subnet count (one instance per AZ for HA)
  # - asg_max_size defaults to calculated capacity based on task requirements
  # When overriding asg_max_size, ensure it's sufficient for task_max_count tasks
  # or ECS may fail to place tasks during scaling events.
  asg_min_size = var.asg_min_size != null ? var.asg_min_size : length(var.asg_subnets)
  asg_max_size = var.asg_max_size != null ? var.asg_max_size : max(
    # How many EC2 instances we need to host task_max_count assuming memory consumption
    # Note: ECS uses memory reservation (soft limit) for task placement decisions when set
    ceil(
      var.task_max_count / ((data.aws_ec2_instance_type.backend.memory_size - 1024 - local.cloudwatch_agent_container_resources.memory) / coalesce(var.container_memory_reservation, var.container_memory))
    ),
    # How many EC2 instances we need to host task_max_count assuming CPU consumption
    ceil(
      var.task_max_count / ((data.aws_ec2_instance_type.backend.default_vcpus * 1024 - local.cloudwatch_agent_container_resources.cpu) / var.container_cpu)
    ),
    # Or at least one more than min size.
    local.asg_min_size + 1
  )

}
