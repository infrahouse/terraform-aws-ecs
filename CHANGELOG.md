# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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