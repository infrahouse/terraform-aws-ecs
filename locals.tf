locals {
  module_version = "3.6.1"

  module_name = "infrahouse/ecs/aws"
  default_module_tags = {
    environment : var.environment
    service : var.service_name
    account : data.aws_caller_identity.current.account_id
    created_by_module : local.module_name
    module_version = local.module_version
  }
}
