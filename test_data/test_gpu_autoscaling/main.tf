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

  # Feature under test: the GPU target-tracking policy. gpu_count > 0 creates the
  # policy and selects the GPU-optimized ECS AMI (ami_id intentionally unset).
  gpu_count         = var.gpu_count
  asg_instance_type = var.instance_type

  # Headroom so the GPU policy can actually move the service: start at one task on
  # one node, allow scaling to two. Without this the policy has nothing to do.
  asg_min_size       = 1
  asg_max_size       = 2
  task_min_count     = 1
  task_max_count     = 2
  task_desired_count = 1

  # Scale out when average GPU utilization exceeds this. The test injects a high
  # value via PutMetricData to trigger it deterministically (no real GPU load).
  gpu_autoscaling_target = var.gpu_autoscaling_target

  # The container is only healthy if nvidia-smi succeeds inside it.
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
