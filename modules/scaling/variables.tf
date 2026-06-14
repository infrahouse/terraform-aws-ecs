variable "instance_memory_mib" {
  type        = number
  description = "Total memory (MiB) of one EC2 instance (data.aws_ec2_instance_type.memory_size)."
}

variable "instance_vcpus" {
  type        = number
  description = "Default vCPUs of one EC2 instance (data.aws_ec2_instance_type.default_vcpus)."
}

variable "instance_gpus" {
  type        = number
  description = <<-EOT
    Number of GPUs on one EC2 instance. Sum of
    data.aws_ec2_instance_type.gpus[*].count, or 0 for non-GPU instance types.
  EOT
}

variable "task_max_count" {
  type        = number
  description = "Highest number of ECS tasks to run."
}

variable "container_cpu" {
  type        = number
  description = "CPU units one task reserves."
}

variable "container_memory" {
  type        = number
  description = "Memory (MiB) one task reserves."
}

variable "container_memory_reservation" {
  type        = number
  description = <<-EOT
    Soft memory reservation (MiB) one task reserves, if set. ECS uses it for
    placement decisions when present; otherwise container_memory is used.
  EOT
  default     = null
}

variable "gpu_count" {
  type        = number
  description = "Number of GPUs one task reserves."
  # The "gpu_count must not exceed the GPUs on one instance" check compares
  # gpu_count against instance_gpus. Cross-variable references in a variable
  # validation require Terraform >= 1.9, but this module supports ~> 1.5, so the
  # check lives in an output precondition (allowed since 1.2) in outputs.tf.
}

variable "daemon_cpu_overhead" {
  type        = number
  description = "CPU units reserved per instance by daemon sidecars (cloudwatch/vector agents)."
}

variable "daemon_memory_overhead" {
  type        = number
  description = "Memory (MiB) reserved per instance by daemon sidecars (cloudwatch/vector agents)."
}

variable "subnet_count" {
  type        = number
  description = "Number of ASG subnets. Default for asg_min_size (one instance per AZ)."
}

variable "consumer_asg_min_size" {
  type        = number
  description = "User-provided ASG min size. If null, defaults to subnet_count."
  default     = null
}

variable "consumer_asg_max_size" {
  type        = number
  description = "User-provided ASG max size. If null, derived from task_max_count and per-instance capacity."
  default     = null
}
