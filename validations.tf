# validations.tf
#
# This file contains cross-variable validation checks using Terraform check blocks.
# These checks will display errors during terraform plan when invalid configurations
# are detected, but provide better error messages than native validation blocks.

# Cross-variable validation: healthcheck interval must be >= timeout
check "healthcheck_interval_greater_than_timeout" {
  assert {
    condition     = var.healthcheck_interval >= var.healthcheck_timeout
    error_message = <<-EOF
      ╔════════════════════════════════════════════════════════════════════════╗
      ║                    ⚠️  CONFIGURATION ERROR ⚠️                          ║
      ╚════════════════════════════════════════════════════════════════════════╝

      Health check interval must be greater than or equal to health check timeout.

      Current configuration:
        - Health check timeout:  ${var.healthcheck_timeout} seconds
        - Health check interval: ${var.healthcheck_interval} seconds

      Problem:
        AWS requires that the interval value is greater than or equal to the timeout value.
        The health check needs enough time to complete before the next check starts.

      Solution:
        Adjust your configuration so that interval >= timeout. For example:

        # Good configuration:
        healthcheck_timeout  = 5   # Time to wait for response
        healthcheck_interval = 10  # Time between checks (default)

      Common configurations:
        - Fast checks:    timeout = 2,  interval = 5
        - Normal checks:  timeout = 5,  interval = 10  (default)
        - Slow checks:    timeout = 10, interval = 30

      ════════════════════════════════════════════════════════════════════════
    EOF
  }
}