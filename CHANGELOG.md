# Changelog

All notable changes to this project will be documented in this file.

## [7.8.0] - 2026-02-28

### Bug Fixes

- Make daemon overhead conditional and document Docker socket security

### Features

- Add Vector Agent daemon support and polish extra target groups
- Add protocol_version, gRPC support, and CI optimization ([#141](https://github.com/infrahouse/terraform-aws-ecs/issues/141))

## [7.7.0] - 2026-02-25

### Bug Fixes

- Respect var.asg_max_size when explicitly set ([#123](https://github.com/infrahouse/terraform-aws-ecs/issues/123))
- Add ALB guard to all extra TG resources and fix set indexing

### Features

- Add extra_target_groups for multi-port container support

### Security

- Harden extra target groups and enable EFS transit encryption

## [7.6.0] - 2026-02-20

## [7.5.0] - 2026-01-28

### Features

- Add Route53 weighted routing for zero-downtime migrations

## [7.4.0] - 2026-01-17

### Bug Fixes

- Respect var.asg_max_size when explicitly set ([#123](https://github.com/infrahouse/terraform-aws-ecs/issues/123))

## [7.3.0] - 2026-01-15

### Features

- Add load balancing algorithm configuration for target groups

## [7.2.0] - 2026-01-07

### Bug Fixes

- Handle null value in memory reservation validation check

### Features

- Add autoscaling target validation and improve test configuration

## [7.1.0] - 2025-12-28

### Features

- Add memory reservation support and CloudWatch monitoring outputs

### Miscellaneous Tasks

- Update terraform registry.infrahouse.com/infrahouse/website-pod/aws to v5.13.0

## [7.0.0] - 2025-12-03

### Bug Fixes

- Handle null KMS key ARN in validation error message

### Documentation

- Update planning documents and add v7.0.0 release summary
- Add comprehensive v7.0.0 migration and KMS encryption documentation
- Add comprehensive v7.0.0 migration and KMS encryption documentation
- Address PR review recommendations and add validations

### Features

- Add CloudWatch KMS encryption and improve module infrastructure
- Add variable validation blocks for input parameters
- Upgrade to website-pod 5.12.1 and add required alarm_emails

### Miscellaneous Tasks

- Improve development tooling and repository configuration

### Testing

- Migrate remaining tests to use subzone for DNS isolation

### Ci

- Increase Terraform CI timeout to 240 minutes

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Support for custom CAA (Certificate Authority Authorization) records via new `certificate_issuers` variable
- Upgraded website-pod module from 5.8.2 to 5.9.0 to enable CAA record support

## [6.0.0] - TBD

### Changed

- **BREAKING**: Default AMI changed from Amazon Linux 2 to Amazon Linux 2023
  - AMI filter updated from `amzn2-ami-ecs-hvm-*` to `al2023-ami-ecs-hvm-*`
  - Existing deployments will gradually replace EC2 instances with AL2023-based instances
  - Users can continue using Amazon Linux 2 by explicitly setting the `ami_id` variable
  - See README.md "Migration from Amazon Linux 2 to Amazon Linux 2023" section for details

### Migration Notes

**For existing users upgrading from v5.x:**

This is a breaking change. When you upgrade to v6.0.0, your autoscaling group will eventually replace all EC2 instances with new instances running Amazon Linux 2023 instead of Amazon Linux 2.

**Option 1: Continue using Amazon Linux 2** (recommended for existing production deployments)
```hcl
module "ecs" {
  source  = "infrahouse/ecs/aws"
  version = "6.0.0"
  ami_id  = "<your-al2-ami-id>"  # Explicitly set to your AL2 AMI
  # ... rest of your configuration
}
```

**Option 2: Adopt Amazon Linux 2023**
- Simply upgrade the module version
- Test thoroughly in non-production environments first
- Plan for instance replacement during a maintenance window
- Monitor ECS task migration during instance replacement

### Why Amazon Linux 2023?

- Extended support lifecycle (5 years per major release)
- Improved security posture with frequent updates
- Better systemd integration
- Deterministic package updates
- Amazon Linux 2 enters maintenance support on June 30, 2024, with end of life on June 30, 2025

For more details on the differences between AL2 and AL2023, see the [AWS documentation](https://docs.aws.amazon.com/linux/al2023/ug/compare-with-al2.html).

## [5.12.0] - Previous Release

### Added
- Support for AWS provider version 6
- Cleanup of ECS task definitions to prevent accumulation

---

## Earlier Releases

See Git history for changes prior to v5.12.0.