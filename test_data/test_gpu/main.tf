module "httpd" {
  source = "../../"
  providers = {
    aws     = aws
    aws.dns = aws
  }
  load_balancer_subnets = var.subnet_public_ids
  asg_subnets           = var.subnet_private_ids
  dns_names             = [""]
  docker_image          = "httpd"
  container_port        = 80
  service_name          = var.service_name
  zone_id               = var.zone_id

  # Feature under test: reserve a GPU and let the module auto-select the
  # GPU-optimized ECS AMI (ami_id intentionally unset). A GPU instance type is
  # still required.
  gpu_count         = var.gpu_count
  asg_instance_type = var.instance_type

  # Keep the smoke test to a single GPU instance / single task to stay cheap.
  asg_min_size       = 1
  asg_max_size       = 1
  task_desired_count = 1

  # The container is only healthy if nvidia-smi succeeds inside it, which
  # proves the GPU device and driver are visible to the container.
  container_healthcheck_command = "nvidia-smi || exit 1"
  container_command = [
    "sh", "-c",
    "echo '<html><body><h1>It works!</h1></body></html>' > /usr/local/apache2/htdocs/index.html && httpd-foreground"
  ]

  enable_cloudwatch_logs   = true
  access_log_force_destroy = true
  alarm_emails             = ["test@example.com"]
  replication_region       = local.replication_region
}

locals {
  replication_region = var.region == "us-east-1" ? "us-west-2" : "us-east-1"
}
