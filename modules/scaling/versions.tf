terraform {
  # Output preconditions that reference input variables (see outputs.tf) are
  # available since Terraform 1.2; mirror the root module's floor of ~> 1.5.
  # This submodule is provider-free, so it declares no required_providers.
  required_version = "~> 1.5"
}
