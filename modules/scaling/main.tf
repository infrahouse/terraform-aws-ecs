locals {
  # Per-instance task capacity by each constraint. Reserve 1024 MiB for the host
  # OS, subtract daemon sidecar overhead, then divide by the per-task reservation.
  mem_capacity_per_instance = (
    (var.instance_memory_mib - 1024 - var.daemon_memory_overhead) /
    coalesce(var.container_memory_reservation, var.container_memory)
  )
  cpu_capacity_per_instance = (
    (var.instance_vcpus * 1024 - var.daemon_cpu_overhead) / var.container_cpu
  )

  instances_for_memory = ceil(var.task_max_count / local.mem_capacity_per_instance)
  instances_for_cpu    = ceil(var.task_max_count / local.cpu_capacity_per_instance)

  # GPU capacity. Each task reserves whole GPUs (gpu_count), so a host fits
  # floor(instance_gpus / gpu_count) GPU tasks. Unlike CPU/memory, GPUs cannot be
  # oversubscribed, so this term often dominates the ASG max size. Guarded so the
  # non-GPU path and a zero gpu_count never divide by zero.
  gpu_tasks_per_instance = (
    var.gpu_count > 0 && var.instance_gpus > 0
    ? floor(var.instance_gpus / var.gpu_count)
    : 0
  )
  instances_for_gpu = (
    var.gpu_count > 0 && local.gpu_tasks_per_instance > 0
    ? ceil(var.task_max_count / local.gpu_tasks_per_instance)
    : 0
  )

  # User-provided values take precedence over the calculated defaults.
  asg_min_size = var.consumer_asg_min_size != null ? var.consumer_asg_min_size : var.subnet_count

  asg_max_size = var.consumer_asg_max_size != null ? var.consumer_asg_max_size : max(
    local.instances_for_memory,
    local.instances_for_cpu,
    local.instances_for_gpu,
    local.asg_min_size + 1,
  )
}
