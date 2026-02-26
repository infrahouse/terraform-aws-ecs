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
  task_role_arn            = aws_iam_role.task_role.arn
  enable_cloudwatch_logs   = true
  access_log_force_destroy = true
  alarm_emails             = ["test@example.com"]

  extra_target_groups = {
    extra = {
      listener_port  = 8081
      container_port = 8081
      # Permissive matcher: httpd doesn't listen on 8081, so the TG
      # health check will get connection-refused (502/503). We only
      # need to verify that the extra TG is wired into the ECS service.
      health_check = {
        matcher = "200-499"
      }
    }
  }
}
