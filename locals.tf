locals {
  module_version = "3.6.1"

  module_name = "infrahouse/ecs/aws"
  tags = {
    created_by_module : local.module_name
    module_version = local.module_version
  }
}
