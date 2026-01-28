# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## First Steps

**Your first tool call in this repository MUST be reading .claude/CODING_STANDARD.md.
Do not read any other files, search, or take any actions until you have read it.**
This contains InfraHouse's comprehensive coding standards for Terraform, Python, and general formatting rules.

## Module Overview

This is `terraform-aws-ecs`, an InfraHouse Terraform module that creates an AWS ECS cluster with EC2 capacity provider to run Docker containers. It provisions:
- ECS Cluster with managed Auto Scaling Group
- Application Load Balancer (ALB) or Network Load Balancer (NLB)
- SSL certificates with automatic DNS validation
- Task-level autoscaling
- CloudWatch logging and alarms
- Optional EFS volume support

## Architecture

The module uses two sub-modules based on `lb_type`:
- `module.pod` (website-pod) - Used for ALB (`lb_type = "alb"`)
- `module.tcp-pod` - Used for NLB (`lb_type = "nlb"`)

Key files:
- `main.tf` - ECS cluster, capacity provider, task definition, and service
- `website-pod.tf` / `tcp-pod.tf` - Load balancer configuration via sub-modules
- `autoscaling.tf` - Task-level autoscaling policies
- `iam.tf` - Task execution role and instance roles
- `cloudwatch.tf` - Log groups for ECS tasks
- `cloudwatch_agent.tf` - Sidecar CloudWatch agent for EC2 metrics
- `locals.tf` - Computed values and ASG sizing calculations

## Development Commands

```bash
# Setup development environment
make bootstrap

# Format code (Terraform + Python)
make format

# Lint code
make lint

# Validate Terraform
make validate

# Run tests (keeps infrastructure for debugging)
make test-keep

# Run tests with cleanup (before PR)
make test-clean

# Run specific test with filter
TEST_PATH=tests/test_httpd.py TEST_FILTER="test_ and aws-6" make test-keep
```

## Testing

Tests use pytest with pytest-infrahouse fixtures and create real AWS infrastructure:
- Test configurations are in `test_data/` (httpd, httpd_autoscaling, httpd_efs, httpd_tcp)
- Tests run against two AWS provider versions: `~> 5.56` and `~> 6.0`
- `conftest.py` contains helper functions like `wait_for_success()` for health checks

To run a single test:
```bash
pytest -xvvs tests/test_httpd.py -k "test_module and aws-6"
```

## Key Variables

Required:
- `service_name`, `docker_image`, `container_port`
- `asg_subnets`, `load_balancer_subnets`
- `zone_id`, `dns_names`
- `alarm_emails`

The module auto-calculates `asg_max_size` based on `task_max_count` and container resource requirements (see `locals.tf:80-92`).

## Providers

Requires two AWS provider aliases:
```hcl
providers = {
  aws     = aws      # Main provider
  aws.dns = aws      # For DNS/Route53 (can be same or different account)
}
```

## Version Management

- Current version tracked in `locals.tf` as `local.module_version`
- Version bumping: `make release-patch`, `make release-minor`, `make release-major`
- CHANGELOG auto-generated with git-cliff
