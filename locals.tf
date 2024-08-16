locals {
  module_version = "3.3.0"

  module_name = "infrahouse/ecs/aws"
  tags = {
    created_by_module : local.module_name
    module_version = local.module_version
  }
}
