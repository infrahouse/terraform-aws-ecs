module "tcp-pod" {
  count   = var.lb_type == "nlb" ? 1 : 0
  source  = "registry.infrahouse.com/infrahouse/tcp-pod/aws"
  version = "0.1.1"
  providers = {
    aws     = aws
    aws.dns = aws.dns
  }
  service_name                          = var.service_name
  environment                           = var.environment
  nlb_name_prefix                       = substr(var.service_name, 0, 6)
  nlb_healthcheck_port                  = "traffic-port"
  nlb_idle_timeout                      = var.alb_idle_timeout
  nlb_healthcheck_response_code_matcher = var.alb_healthcheck_response_code_matcher
  nlb_healthcheck_interval              = var.alb_healthcheck_interval
  health_check_grace_period             = var.asg_health_check_grace_period
  health_check_type                     = "EC2"
  attach_target_group_to_asg            = false
  instance_type                         = var.asg_instance_type
  asg_min_size                          = var.asg_min_size
  asg_max_size                          = var.asg_max_size
  asg_scale_in_protected_instances      = "Refresh"
  subnets                               = var.load_balancer_subnets
  backend_subnets                       = var.asg_subnets
  zone_id                               = var.zone_id
  dns_a_records                         = var.dns_names
  ami                                   = var.ami_id == null ? data.aws_ami.ecs.image_id : var.ami_id
  key_pair_name                         = data.aws_key_pair.ssh_key_pair.key_name
  target_group_port                     = var.container_port
  userdata                              = data.cloudinit_config.ecs.rendered
  instance_profile_permissions          = data.aws_iam_policy_document.instance_policy.json
  protect_from_scale_in                 = true # this is to allow ECS manage ASG instances
  autoscaling_target_cpu_load           = var.autoscaling_target_cpu_usage
  root_volume_size                      = var.root_volume_size
  ssh_cidr_block                        = var.ssh_cidr_block
  tags = {
    Name : var.service_name
    AmazonECSManaged : true
    parent_module : local.module_name
    parent_module_version : local.module_version
  }
}
