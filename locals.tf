locals {
  module_version = "4.2.1"

  module_name = "infrahouse/ecs/aws"
  default_module_tags = merge(
    {
      environment : var.environment
      service : var.service_name
      account : data.aws_caller_identity.current.account_id
      created_by_module : local.module_name
      module_version = local.module_version
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
  instance_role_policy_name       = var.lb_type == "alb" ? module.pod[0].instance_role_policy_name : module.tcp-pod[0].instance_role_policy_name
  instance_role_policy_attachment = var.lb_type == "alb" ? module.pod[0].instance_role_policy_attachment : module.tcp-pod[0].instance_role_policy_attachment

}

