data "aws_key_pair" "ssh_key_pair" {
  key_name = var.ssh_key_name
}

module "pod" {
  source = "infrahouse/website-pod/aws"
  providers = {
    aws     = aws
    aws.dns = aws.dns
  }
  version               = "~> 2.0"
  environment           = var.environment
  ami                   = data.aws_ami.ecs.image_id
  backend_subnets       = var.asg_subnets
  zone_id               = var.zone_id
  dns_a_records         = [var.service_name]
  internet_gateway_id   = var.internet_gateway_id
  key_pair_name         = data.aws_key_pair.ssh_key_pair.key_name
  target_group_port     = var.container_port
  alb_healthcheck_path  = var.alb_healthcheck_path
  alb_healthcheck_port  = var.container_port
  subnets               = var.load_balancer_subnets
  userdata              = data.cloudinit_config.ecs.rendered
  instance_profile      = "${var.service_name}_instance"
  webserver_permissions = data.aws_iam_policy_document.instance_policy.json
  asg_min_size          = 2 * var.container_desired_count
  asg_min_elb_capacity  = var.container_desired_count
  service_name          = var.service_name
  alb_name_prefix       = substr(var.service_name, 0, 6)
  tags = {
    Name : var.service_name
  }
}
