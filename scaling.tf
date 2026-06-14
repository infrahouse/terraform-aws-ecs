# ASG sizing math lives in the provider-free ./modules/scaling submodule so it
# can be unit-tested offline with `terraform test` (see tests/math.tftest.hcl).
# The data-source read of the instance type stays here; only plain numbers are
# passed into the submodule.

locals {
  # data.aws_ec2_instance_type.gpus is an empty list for non-GPU instance types,
  # and sum() errors on an empty list, so guard it.
  instance_gpus = (
    length(data.aws_ec2_instance_type.backend.gpus) > 0
    ? sum([for gpu in data.aws_ec2_instance_type.backend.gpus : gpu.count])
    : 0
  )
}

module "scaling" {
  source = "./modules/scaling"

  instance_memory_mib          = data.aws_ec2_instance_type.backend.memory_size
  instance_vcpus               = data.aws_ec2_instance_type.backend.default_vcpus
  instance_gpus                = local.instance_gpus
  task_max_count               = var.task_max_count
  container_cpu                = var.container_cpu
  container_memory             = var.container_memory
  container_memory_reservation = var.container_memory_reservation
  gpu_count                    = var.gpu_count
  daemon_cpu_overhead          = local.daemon_cpu_overhead
  daemon_memory_overhead       = local.daemon_memory_overhead
  subnet_count                 = length(var.asg_subnets)
  consumer_asg_min_size        = var.asg_min_size
  consumer_asg_max_size        = var.asg_max_size
}
