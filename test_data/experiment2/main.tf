module "vllm" {
  source = "../../"
  providers = {
    aws     = aws
    aws.dns = aws
  }

  load_balancer_subnets = var.subnet_public_ids
  asg_subnets           = var.subnet_private_ids
  dns_names             = [""]
  service_name          = var.service_name
  zone_id               = var.zone_id
  alarm_emails          = ["test@example.com"]

  # vLLM image with fetch_model.sh baked in; OpenAI API on :8000.
  docker_image   = var.docker_image
  container_port = 8000

  # The module defaults (cpu 200, memory 128 MB) would OOM-kill the model fetch
  # and vLLM immediately. Give the single task most of the g5.2xlarge
  # (8 vCPU / 32 GiB), leaving headroom for the ECS + CloudWatch agents and OS.
  container_cpu    = 7168
  container_memory = 28672

  # Feature under test: one GPU per task on a GPU instance type. ami_id is unset,
  # so the module auto-selects the GPU-optimized ECS AMI.
  gpu_count         = 1
  asg_instance_type = var.instance_type

  # The ~15 GB model is fetched onto the root volume (the module does not expose
  # instance-store mounting); give it room.
  root_volume_size = 100

  # One task per node; pin the fleet so the test cost is predictable.
  asg_min_size       = var.node_count
  asg_max_size       = var.node_count
  task_desired_count = var.node_count
  task_max_count     = var.node_count

  # vLLM downloads and loads the model on start (several minutes). Use vLLM's
  # /health for both the container health check and the ALB target health check,
  # and give the service a long health-check grace period: ECS ignores failing
  # container, ELB, and Route53 health checks for this window after a task starts,
  # so the task is not replaced while the model is still loading. Once loaded,
  # /health returns 200 and the task/target become healthy. (curl is not in the
  # vLLM image, so the container check uses python3, which is.)
  # Use 127.0.0.1, not localhost: localhost can resolve to ::1 (IPv6) first, but
  # vLLM binds IPv4 (--host 0.0.0.0), so localhost fails with EADDRNOTAVAIL.
  # Keep the import/urlopen at column 0 after <<- strips the common indent;
  # python is whitespace-sensitive, so don't visually nest these lines.
  container_healthcheck_command             = <<-EOT
    python3 -c "
    import urllib.request
    urllib.request.urlopen('http://127.0.0.1:8000/health', timeout=3)
    " || exit 1
  EOT
  healthcheck_path                          = "/health"
  service_health_check_grace_period_seconds = 1200
  asg_health_check_grace_period             = 1200

  # Model lands here on the host and is mounted into the container at /models.
  task_local_volumes = {
    models = {
      host_path      = "/var/models"
      container_path = "/models"
    }
  }

  task_environment_variables = [
    { name = "MODEL_SRC", value = var.model_src },
    { name = "MODEL_DIR", value = "/models" },
    { name = "VLLM_MAX_MODEL_LEN", value = tostring(var.max_model_len) },
    { name = "FETCH_BACKEND", value = "http" },
    { name = "HF_XET_HIGH_PERFORMANCE", value = "1" },
  ]

  enable_cloudwatch_logs   = true
  access_log_force_destroy = true
  replication_region       = local.replication_region
}

locals {
  replication_region = var.region == "us-east-1" ? "us-west-2" : "us-east-1"
}
