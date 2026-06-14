check "ecr_image_tagging_requires_ecr_uri" {
  assert {
    condition = (
      var.enable_ecr_image_tagging
      ? can(regex("dkr\\.ecr\\.[^.]+\\.amazonaws\\.com/", var.docker_image))
      : true
    )
    error_message = "docker_image must be an ECR image URI when enable_ecr_image_tagging is true. Got: ${var.docker_image}"
  }
}

check "asg_size_validation" {
  assert {
    condition = (
      var.asg_min_size == null || var.asg_max_size == null
      ? true
      : var.asg_max_size >= var.asg_min_size
    )
    error_message = "asg_max_size (${coalesce(var.asg_max_size, "auto")}) must be greater than or equal to asg_min_size (${coalesce(var.asg_min_size, "auto")}) when both are explicitly set."
  }
}

locals {
  module_version = "8.2.0"

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

  # AMI selection: an explicit ami_id always wins. Otherwise GPU workloads get
  # the GPU-optimized ECS AMI (which ships the NVIDIA drivers) and everything else
  # gets the standard ECS AMI. nonsensitive() unwraps the SSM parameter value,
  # which is a public AMI id, not a secret.
  selected_ami = (
    var.ami_id != null
    ? var.ami_id
    : (
      var.gpu_count > 0
      ? nonsensitive(data.aws_ssm_parameter.ecs_gpu_ami[0].value)
      : data.aws_ami.ecs.image_id
    )
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
  acm_certificate_arn             = var.lb_type == "alb" ? module.pod[0].acm_certificate_arn : null

  cloudwatch_agent_config_path = "/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json"
  cloudwatch_agent_container_resources = {
    cpu    = 128
    memory = 256
  }

  vector_agent_config_path = "/etc/vector/vector.yaml"
  vector_agent_container_resources = {
    cpu    = 128
    memory = 256
  }

  # ECR repository ARN extracted from var.docker_image for scoped IAM permissions.
  # ECR URI format: ACCOUNT.dkr.ecr.REGION.amazonaws.com/REPO:TAG or /REPO@sha256:DIGEST
  # The can() wrapper prevents a plan-time crash if docker_image is not an ECR URI
  # (the check block above warns the user with a clear message).
  ecr_image_repo_arn = (
    var.enable_ecr_image_tagging && can(regex("dkr\\.ecr\\.([^.]+)\\.amazonaws\\.com", var.docker_image))
    ? "arn:aws:ecr:${
      regex("dkr\\.ecr\\.([^.]+)\\.amazonaws\\.com", var.docker_image)[0]
      }:${
      data.aws_caller_identity.current.account_id
      }:repository/${
      regex("amazonaws\\.com/([^:@]+)", var.docker_image)[0]
    }"
    : null
  )

  # Total daemon overhead per EC2 instance
  daemon_memory_overhead = (
    (var.enable_cloudwatch_logs ? local.cloudwatch_agent_container_resources.memory : 0) +
    (var.enable_vector_agent ? local.vector_agent_container_resources.memory : 0)
  )
  daemon_cpu_overhead = (
    (var.enable_cloudwatch_logs ? local.cloudwatch_agent_container_resources.cpu : 0) +
    (var.enable_vector_agent ? local.vector_agent_container_resources.cpu : 0)
  )

  # ASG sizing is resolved by the provider-free ./modules/scaling submodule (see
  # scaling.tf and tests/math.tftest.hcl). User-provided values take precedence;
  # otherwise sizes derive from task_max_count and the instance's CPU, memory,
  # and GPU capacity.
  asg_min_size = module.scaling.asg_min_size
  asg_max_size = module.scaling.asg_max_size
}
