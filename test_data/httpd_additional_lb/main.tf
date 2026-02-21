resource "aws_alb_target_group" "extra" {
  name     = "${var.service_name}-extra"
  port     = 4317
  protocol = "HTTP"
  vpc_id   = data.aws_subnet.first.vpc_id
}

data "aws_subnet" "first" {
  id = var.subnet_private_ids[0]
}

module "httpd" {
  source = "../../"
  providers = {
    aws     = aws
    aws.dns = aws
  }
  load_balancer_subnets         = var.subnet_public_ids
  asg_subnets                   = var.subnet_private_ids
  dns_names                     = ["", "www"]
  docker_image                  = "httpd"
  container_port                = 80
  service_name                  = var.service_name
  zone_id                       = var.zone_id
  container_healthcheck_command = "ls"
  container_command = [
    "sh", "-c",
    "echo '<html><body><h1>It works!</h1></body></html>' > /usr/local/apache2/htdocs/index.html && httpd-foreground"
  ]
  access_log_force_destroy = true
  alarm_emails             = ["test@example.com"]
  additional_load_balancers = [
    {
      target_group_arn = aws_alb_target_group.extra.arn
      container_port   = 4317
    }
  ]
}
