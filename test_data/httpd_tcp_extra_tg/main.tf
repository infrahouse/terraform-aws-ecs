module "httpd" {
  source = "../../"
  providers = {
    aws     = aws
    aws.dns = aws
  }
  load_balancer_subnets         = var.subnet_public_ids
  asg_subnets                   = var.subnet_private_ids
  dns_names                     = ["tcp-extra-tg"]
  docker_image                  = "httpd"
  container_port                = 80
  service_name                  = var.service_name
  zone_id                       = var.zone_id
  task_desired_count            = 1
  asg_max_size                  = 1
  asg_min_size                  = 1
  container_healthcheck_command = "ls"
  container_command = [
    "sh", "-c",
    join(" && ", [
      "echo '<html><body><h1>It works!</h1></body></html>' > /usr/local/apache2/htdocs/index.html",
      # httpd also listens on 8080, the container port of the extra target group.
      "echo 'Listen 8080' >> /usr/local/apache2/conf/httpd.conf",
      "httpd-foreground",
    ])
  ]
  healthcheck_interval = 10
  lb_type              = "nlb"
  alarm_emails         = ["test@example.com"]
  ingress_cidr_blocks  = var.ingress_cidr_blocks

  extra_target_groups = {
    extra = {
      listener_port  = 8080
      container_port = 8080
    }
  }
}
