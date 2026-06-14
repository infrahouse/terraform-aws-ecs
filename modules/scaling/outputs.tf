output "asg_min_size" {
  description = "Resolved ASG minimum size."
  value       = local.asg_min_size
}

output "asg_max_size" {
  description = "Resolved ASG maximum size."
  value       = local.asg_max_size

  precondition {
    # A task cannot span instances, so it can never reserve more GPUs than a
    # single instance provides. instance_gpus == 0 is allowed: that is the
    # separate "no GPU instance type / AMI" misconfiguration, which the root
    # module's gpu_count documentation already covers.
    condition     = var.gpu_count == 0 || var.instance_gpus == 0 || var.gpu_count <= var.instance_gpus
    error_message = <<-EOT
      gpu_count (${var.gpu_count}) exceeds the GPUs on one instance (${var.instance_gpus}).
      A task cannot span instances; pick a larger GPU instance type or lower gpu_count.
    EOT
  }
}
