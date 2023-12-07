data "aws_key_pair" "ssh_key_pair" {
  key_name = var.ssh_key_name
}

module "pod" {
  source = "infrahouse/website-pod/aws"
  providers = {
    aws     = aws
    aws.dns = aws.dns
  }
  version                     = "~> 2.4"
  service_name                = var.service_name
  environment                 = var.environment
  alb_name_prefix             = substr(var.service_name, 0, 6)
  alb_healthcheck_enabled     = true
  alb_healthcheck_port        = "traffic-port"
  alb_healthcheck_path        = var.alb_healthcheck_path
  alb_idle_timeout            = var.alb_idle_timeout
  health_check_type           = "EC2"
  attach_tagret_group_to_asg  = false
  asg_min_size                = var.asg_min_size
  asg_max_size                = var.asg_max_size
  subnets                     = var.load_balancer_subnets
  backend_subnets             = var.asg_subnets
  zone_id                     = var.zone_id
  dns_a_records               = var.dns_names
  ami                         = data.aws_ami.ecs.image_id
  key_pair_name               = data.aws_key_pair.ssh_key_pair.key_name
  target_group_port           = var.container_port
  userdata                    = data.cloudinit_config.ecs.rendered
  instance_profile            = "${var.service_name}_instance"
  webserver_permissions       = data.aws_iam_policy_document.instance_policy.json
  internet_gateway_id         = var.internet_gateway_id
  protect_from_scale_in       = true # this is to allow ECS manage ASG instances
  autoscaling_target_cpu_load = var.autoscaling_target_cpu_usage
  tags = {
    Name : var.service_name
    AmazonECSManaged : true
  }
}
