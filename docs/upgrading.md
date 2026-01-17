# Upgrading Guide

This document covers migration steps between major versions of terraform-aws-ecs.

## Migration from v6.x to v7.0

**Breaking Change (v7.0.0):** The `alarm_emails` variable is now required for CloudWatch alerting.

### What Changed

- **New Required Variable:** `alarm_emails` must be provided
- **Module Dependency Update:** `infrahouse/website-pod/aws` upgraded from 5.9.0 to 5.12.1
- This enables CloudWatch alerts for service health monitoring (high latency, low success rate,
  unhealthy hosts)

### Why This Change

Starting with v7.0.0, the module requires email addresses for CloudWatch alarm notifications.
This ensures that critical service health issues are immediately reported to the appropriate
team members.

### Migration Steps

**Before (v6.x):**

```hcl
module "ecs_service" {
  source  = "infrahouse/ecs/aws"
  version = "~> 6.0"

  service_name       = "my-service"
  environment        = "production"
  # ... other parameters
}
```

**After (v7.0):**

```hcl
module "ecs_service" {
  source  = "infrahouse/ecs/aws"
  version = "~> 7.0"

  service_name       = "my-service"
  environment        = "production"
  alarm_emails       = ["devops@example.com", "oncall@example.com"]  # REQUIRED
  # ... other parameters
}
```

### Email Validation

The `alarm_emails` variable includes validation to ensure:

- At least one email address is provided
- All email addresses are in valid format

Example with multiple emails:

```hcl
alarm_emails = [
  "devops-team@example.com",
  "oncall@example.com",
  "infrastructure-alerts@example.com"
]
```

### What Alerts Are Sent

With `alarm_emails` configured, you'll receive CloudWatch alerts for:

- **High Latency:** Target response time exceeds threshold
- **Low Success Rate:** HTTP error rate is too high
- **Unhealthy Hosts:** Target health checks are failing

These alerts help ensure your ECS service maintains high availability and performance.

**Important:** After first deployment, check your inbox for SNS subscription confirmation emails.
You must click "Confirm subscription" in each email to start receiving alerts.

---

## Behavioral Changes in v7.0

In addition to the required `alarm_emails` parameter, v7.0.0 includes several behavioral changes
that may affect costs and scaling behavior. **Review these carefully before upgrading.**

### 1. CloudWatch Logs Now Enabled by Default

**Change:** The `enable_cloudwatch_logs` variable default changed from `false` to `true`.

**Impact:**

- CloudWatch log groups will be created automatically
- Container logs will be sent to CloudWatch (incurs costs)
- **Estimated Costs:** ~$0.50/GB ingested + $0.03/GB stored per month
- For a typical service logging 1GB/day: ~$15-20/month

**What Logs Are Collected:**

- Container application logs (stdout/stderr)
- EC2 instance system logs (syslog)
- EC2 instance kernel logs (dmesg)

**Migration Actions:**

**Option 1 - Keep logging enabled (recommended):**

```hcl
# No action needed - logging will be enabled automatically
module "ecs_service" {
  source  = "infrahouse/ecs/aws"
  version = "~> 7.0"

  alarm_emails = ["devops@example.com"]
  # enable_cloudwatch_logs defaults to true
  # ... other parameters
}
```

**Option 2 - Disable logging to maintain v6.x behavior:**

```hcl
module "ecs_service" {
  source  = "infrahouse/ecs/aws"
  version = "~> 7.0"

  alarm_emails            = ["devops@example.com"]
  enable_cloudwatch_logs  = false  # Disable logging
  # ... other parameters
}
```

**Option 3 - Reduce retention to control costs:**

```hcl
module "ecs_service" {
  source  = "infrahouse/ecs/aws"
  version = "~> 7.0"

  alarm_emails                   = ["devops@example.com"]
  cloudwatch_log_group_retention = 7  # Keep logs for 7 days instead of 90
  # ... other parameters
}
```

### 2. CPU Autoscaling Target Lowered to 60%

**Change:** The `autoscaling_target_cpu_usage` default changed from 80% to 60%.

**Impact:**

- ECS services will scale out earlier when CPU usage increases
- More instances may run to maintain lower CPU usage
- Better performance headroom, but potentially higher costs
- Aligns with `website-pod` module default for consistency

**When This Matters:**

- If you rely on the default value (didn't explicitly set it)
- For CPU-based autoscaling configurations

**Migration Actions:**

**Option 1 - Keep new 60% target (recommended):**

```hcl
# No action needed - 60% provides better performance headroom
module "ecs_service" {
  source  = "infrahouse/ecs/aws"
  version = "~> 7.0"

  alarm_emails            = ["devops@example.com"]
  autoscaling_metric      = "ECSServiceAverageCPUUtilization"
  # autoscaling_target_cpu_usage defaults to 60
  # ... other parameters
}
```

**Option 2 - Maintain previous 80% target:**

```hcl
module "ecs_service" {
  source  = "infrahouse/ecs/aws"
  version = "~> 7.0"

  alarm_emails                 = ["devops@example.com"]
  autoscaling_metric           = "ECSServiceAverageCPUUtilization"
  autoscaling_target_cpu_usage = 80  # Use previous default
  # ... other parameters
}
```

**Choosing the Right Target:**

- **50-60%:** Better performance, higher cost, more headroom for traffic spikes
- **70%:** Balanced approach
- **80%:** More cost-efficient, less headroom for sudden load increases

### 3. Output Format Change: cloudwatch_log_group_names

**Change:** The `cloudwatch_log_group_names` output changed from a list to a map for better
usability.

**Impact:** If you reference this output in downstream Terraform code, you must update the
access pattern.

**Before (v6.x):**

```hcl
# Access by numeric index (brittle - order-dependent)
locals {
  ecs_log_group    = module.ecs.cloudwatch_log_group_names[0]
  syslog_log_group = module.ecs.cloudwatch_log_group_names[1]
  dmesg_log_group  = module.ecs.cloudwatch_log_group_names[2]
}
```

**After (v7.0):**

```hcl
# Access by descriptive name (more intuitive)
locals {
  ecs_log_group    = module.ecs.cloudwatch_log_group_names["ecs"]
  syslog_log_group = module.ecs.cloudwatch_log_group_names["syslog"]
  dmesg_log_group  = module.ecs.cloudwatch_log_group_names["dmesg"]
}

# Or use the new singular output for the main log group:
locals {
  ecs_log_group = module.ecs.cloudwatch_log_group_name
}
```

**Migration Action:** Update any downstream Terraform code that references
`cloudwatch_log_group_names`.

### 4. Internet Gateway Auto-Detection

**Change:** The `internet_gateway_id` parameter has been removed. The module now automatically
detects the Internet Gateway from your VPC.

**Impact:** Configurations with explicit `internet_gateway_id` will get an "unknown variable"
error.

**Before (v6.x):**

```hcl
module "ecs_service" {
  source  = "infrahouse/ecs/aws"
  version = "~> 6.0"

  internet_gateway_id = data.aws_internet_gateway.main.id  # Explicit parameter
  # ... other parameters
}
```

**After (v7.0):**

```hcl
module "ecs_service" {
  source  = "infrahouse/ecs/aws"
  version = "~> 7.0"

  # internet_gateway_id removed - auto-discovered from VPC
  # ... other parameters
}
```

**Migration Action:** Simply remove the `internet_gateway_id` parameter from your configuration.
The module will automatically discover it.

---

## Migration from Amazon Linux 2 to Amazon Linux 2023

**Breaking Change (v6.0.0+):** This module now defaults to Amazon Linux 2023 (AL2023)
ECS-optimized AMIs instead of Amazon Linux 2.

### What Changed

- Default AMI filter changed from `amzn2-ami-ecs-hvm-*` to `al2023-ami-ecs-hvm-*`
- This affects all new ECS instances launched by the autoscaling group

### Migration Path

**Option 1: Stay on Amazon Linux 2 (Recommended for existing deployments)**

If you want to continue using Amazon Linux 2, explicitly set the `ami_id` variable:

```hcl
module "httpd" {
  source  = "infrahouse/ecs/aws"
  version = "7.3.0"
  ami_id  = "<your-al2-ami-id>"  # Lock to Amazon Linux 2
  # ... other configuration
}
```

**Option 2: Migrate to Amazon Linux 2023**

To adopt AL2023, simply upgrade the module version. Note that existing instances will need to
be replaced:

1. The autoscaling group will gradually replace instances with AL2023-based ones
2. During replacement, ECS tasks will be migrated to new instances
3. Test thoroughly in a non-production environment first

### Key Differences

- AL2023 uses systemd-based initialization (cloud-init still supported)
- Different default package versions
- Improved security posture and longer support lifecycle
- See [AWS AL2023 documentation](https://docs.aws.amazon.com/linux/al2023/ug/compare-with-al2.html)
  for detailed differences

### Custom AMIs

If you use custom AMIs based on Amazon Linux 2, you must:

- Rebuild your AMIs based on AL2023, OR
- Explicitly set the `ami_id` variable to your custom AL2 AMI