output "asg_min_size" {
  description = "Resolved ASG minimum size."
  value       = local.asg_min_size
}

output "asg_max_size" {
  description = "Resolved ASG maximum size."
  value       = local.asg_max_size

  precondition {
    condition     = local.task_memory_mib + var.daemon_memory_overhead < var.instance_memory_mib
    error_message = <<-EOT
      The task and daemon memory reservations leave no memory for the host.
      Pick a larger instance type or lower container_memory/container_memory_reservation.
    EOT
  }

  precondition {
    condition     = local.cpu_tasks_per_instance >= 1
    error_message = <<-EOT
      The configured task needs more CPU than one instance can reserve.
      Pick a larger instance type or lower container_cpu.
    EOT
  }

  precondition {
    condition     = var.gpu_count == 0 || local.gpu_tasks_per_instance >= 1
    error_message = <<-EOT
      gpu_count (${var.gpu_count}) exceeds the GPUs on one instance (${var.instance_gpus}).
      A task cannot span instances; pick a GPU instance type with enough GPUs or lower gpu_count.
    EOT
  }

  precondition {
    condition     = local.can_stop_at_min_count || local.can_start_at_min_count
    error_message = <<-EOT
      ECS cannot make a rolling-deployment move at task_min_count (${var.task_min_count}) with
      deployment_minimum_healthy_percent=${var.deployment_minimum_healthy_percent} and
      deployment_maximum_percent=${var.deployment_maximum_percent}. Allow ECS to stop one old
      task or start one replacement at the minimum desired count.
    EOT
  }

  precondition {
    condition     = var.consumer_asg_max_size == null ? true : var.consumer_asg_max_size >= local.required_instances
    error_message = <<-EOT
      asg_max_size (${coalesce(var.consumer_asg_max_size, 0)}) is below the ${local.required_instances}
      instances required for ${local.required_task_slots} task slots during deployment.
      Set asg_max_size to at least ${local.required_instances}, or null to use the calculated default.
    EOT
  }
}
