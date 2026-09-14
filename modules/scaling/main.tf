locals {
  # Per-instance task capacity by each constraint. Reserve 1024 MiB for the host
  # OS, subtract daemon sidecar overhead, then divide by the per-task reservation.
  task_memory_mib = coalesce(var.container_memory_reservation, var.container_memory)
  memory_tasks_per_instance = max(
    1,
    floor(
      (var.instance_memory_mib - 1024 - var.daemon_memory_overhead) /
      local.task_memory_mib
    )
  )
  cpu_tasks_per_instance = floor(
    (var.instance_vcpus * 1024 - var.daemon_cpu_overhead) / var.container_cpu
  )

  # GPU capacity. Each task reserves whole GPUs (gpu_count), so a host fits
  # floor(instance_gpus / gpu_count) GPU tasks. Unlike CPU/memory, GPUs cannot be
  # oversubscribed, so this term often dominates the ASG max size. Guarded so the
  # non-GPU path and a zero gpu_count never divide by zero.
  gpu_tasks_per_instance = (
    var.gpu_count > 0
    ? floor(var.instance_gpus / var.gpu_count)
    : 0
  )

  # A deployment must be able to stop an old task or start a replacement at
  # every desired count. Both moves become no harder as desired count rises, so
  # validating task_min_count covers the configured autoscaling range.
  minimum_healthy_at_min_count = ceil(
    var.task_min_count * var.deployment_minimum_healthy_percent / 100
  )
  maximum_running_at_min_count = floor(
    var.task_min_count * var.deployment_maximum_percent / 100
  )
  can_stop_at_min_count  = local.minimum_healthy_at_min_count <= var.task_min_count - 1
  can_start_at_min_count = local.maximum_running_at_min_count >= var.task_min_count + 1

  minimum_healthy_at_max_count = ceil(
    var.task_max_count * var.deployment_minimum_healthy_percent / 100
  )
  can_stop_at_max_count = local.minimum_healthy_at_max_count <= var.task_max_count - 1
  required_task_slots   = var.task_max_count + (local.can_stop_at_max_count ? 0 : 1)

  # max(1, ...) keeps evaluation safe so the output preconditions below can
  # report an actionable error when a task cannot fit on one host.
  instances_for_memory = ceil(local.required_task_slots / local.memory_tasks_per_instance)
  instances_for_cpu    = ceil(local.required_task_slots / max(1, local.cpu_tasks_per_instance))
  instances_for_gpu = (
    var.gpu_count > 0
    ? ceil(local.required_task_slots / max(1, local.gpu_tasks_per_instance))
    : 0
  )

  # User-provided values take precedence over the calculated defaults.
  asg_min_size = var.consumer_asg_min_size != null ? var.consumer_asg_min_size : var.subnet_count

  required_instances = max(
    local.instances_for_memory,
    local.instances_for_cpu,
    local.instances_for_gpu,
    local.asg_min_size,
  )
  automatic_asg_max_size = max(local.required_instances, local.asg_min_size + 1)
  asg_max_size = (
    var.consumer_asg_max_size != null
    ? var.consumer_asg_max_size
    : local.automatic_asg_max_size
  )
}
