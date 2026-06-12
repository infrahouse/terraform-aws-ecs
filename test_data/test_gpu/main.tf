module "httpd" {
  source = "../../"
  providers = {
    aws     = aws
    aws.dns = aws
  }
  load_balancer_subnets         = var.subnet_public_ids
  asg_subnets                   = var.subnet_private_ids
  dns_names                     = [""]
  docker_image                  = "httpd"
  container_port                = 80
  service_name                  = var.service_name
  zone_id                       = var.zone_id
  container_healthcheck_command = "ls"
  container_command = [
    "sh", "-c",
    "echo '<html><body><h1>It works!</h1></body></html>' > /usr/local/apache2/htdocs/index.html && httpd-foreground"
  ]
  enable_cloudwatch_logs   = true
  access_log_force_destroy = true
  alarm_emails             = ["test@example.com"]
  gpu_count                = var.gpu_count
  replication_region       = local.replication_region
}

locals {
  replication_region = var.region == "us-east-1" ? "us-west-2" : "us-east-1"
}
