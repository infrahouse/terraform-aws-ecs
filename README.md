# terraform-aws-ecs
The module creates an Elastic Container Service and runs one docker image in it.

![ECS.drawio.png](assets/ECS.drawio.png)

A user is expected to create a VPC, subnets 
(See the [service network](https://github.com/infrahouse/terraform-aws-service-network) module if you need to do it),
and a Route53 zone.

The module uses the [infrahouse/website-pod/aws](https://registry.terraform.io/modules/infrahouse/website-pod/aws/latest)
module to create a load balancer, autoscaling group, and update DNS.

## Usage

Basically, you need to pass the docker image and subnets where to place a load balancer 
and autoscaling group.

The module will create an SSL certificate and a DNS record. If the `dns_names` is `["www"]` 
and the zone is "domain.com", the module will create a record "www.domain.com". 
You can specify more than one DNS name, then the module will create DNS records for all of them 
and the certificate will list them as aliases. You can also specify an empty name - `dns_names = ["", "www"]` - 
if you want a popular setup https://domain.com + https://www.domain.com/.

For usage see how the module is used in the using tests in `test_data/test_module`.

## Migration from v6.x to v7.0

**Breaking Change (v7.0.0):** The `alarm_emails` variable is now required for CloudWatch alerting.

### What Changed
- **New Required Variable:** `alarm_emails` must be provided
- **Module Dependency Update:** `infrahouse/website-pod/aws` upgraded from 5.9.0 to 5.12.1
- This enables CloudWatch alerts for service health monitoring (high latency, low success rate, unhealthy hosts)

### Why This Change
Starting with v7.0.0, the module requires email addresses for CloudWatch alarm notifications. This ensures that critical service health issues are immediately reported to the appropriate team members.

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

In addition to the required `alarm_emails` parameter, 
v7.0.0 includes several behavioral changes that may affect costs and scaling behavior. 
**Review these carefully before upgrading.**

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

**Change:** The `cloudwatch_log_group_names` output changed from a list to a map for better usability.

**Impact:** If you reference this output in downstream Terraform code, you must update the access pattern.

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

**Migration Action:** Update any downstream Terraform code that references `cloudwatch_log_group_names`.

### 4. Internet Gateway Auto-Detection

**Change:** The `internet_gateway_id` parameter has been removed. The module now automatically detects the Internet Gateway from your VPC.

**Impact:** Configurations with explicit `internet_gateway_id` will get an "unknown variable" error.

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

## CloudWatch Logs KMS Encryption

The module supports encrypting CloudWatch logs with a customer-managed KMS key for enhanced security and compliance.
By default, CloudWatch uses AWS-managed encryption, but you can provide your own KMS key for additional control.

### Why Use KMS Encryption?

**AWS-Managed Encryption (default):**
- ✅ No additional configuration required
- ✅ No cost for key management
- ❌ No control over key rotation or access policies
- ❌ Cannot meet compliance requirements for customer-managed keys

**Customer-Managed KMS Key:**
- ✅ Full control over key policies and access
- ✅ Custom key rotation schedules
- ✅ Detailed CloudTrail audit logs of key usage
- ✅ Meets compliance requirements (HIPAA, PCI-DSS, etc.)
- ❌ Additional AWS KMS costs (~$1/month per key + usage)

### Creating a KMS Key for CloudWatch Logs

To enable KMS encryption, you must create a KMS key with proper permissions for the CloudWatch Logs service:

```hcl
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

data "aws_iam_policy_document" "cloudwatch_logs_kms" {
  statement {
    sid    = "Enable IAM User Permissions"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
    actions   = ["kms:*"]
    resources = ["*"]
  }

  statement {
    sid    = "Allow CloudWatch Logs"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["logs.${data.aws_region.current.name}.amazonaws.com"]
    }
    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:CreateGrant",
      "kms:DescribeKey"
    ]
    resources = ["*"]

    condition {
      test     = "ArnLike"
      variable = "kms:EncryptionContext:aws:logs:arn"
      values   = ["arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:*"]
    }
  }
}

resource "aws_kms_key" "cloudwatch_logs" {
  description             = "KMS key for ECS CloudWatch Logs encryption"
  deletion_window_in_days = 30
  enable_key_rotation     = true
  policy                  = data.aws_iam_policy_document.cloudwatch_logs_kms.json

  tags = {
    Name        = "ecs-cloudwatch-logs-key"
    Environment = "production"
  }
}

resource "aws_kms_alias" "cloudwatch_logs" {
  name          = "alias/ecs-cloudwatch-logs"
  target_key_id = aws_kms_key.cloudwatch_logs.key_id
}
```

### Using the KMS Key with the ECS Module

```hcl
module "ecs_service" {
  source  = "infrahouse/ecs/aws"
  version = "~> 7.0"

  service_name              = "my-service"
  environment               = "production"
  alarm_emails              = ["devops@example.com"]

  # Enable KMS encryption for CloudWatch logs
  cloudwatch_log_kms_key_id = aws_kms_key.cloudwatch_logs.arn

  # CloudWatch logs configuration
  enable_cloudwatch_logs         = true
  cloudwatch_log_group_retention = 90  # Keep encrypted logs for 90 days

  # ... other parameters
}
```

### Important Requirements

1. **Region Matching**: The KMS key MUST be in the same AWS region as the CloudWatch log groups
2. **Service Principal**: Use the regional service principal format: `logs.REGION.amazonaws.com`
3. **Encryption Context**: The condition must include the proper encryption context for log groups
4. **Permissions**: The CloudWatch Logs service needs `kms:GenerateDataKey*` and `kms:CreateGrant` permissions

### Troubleshooting KMS Encryption

**Error: "User is not authorized to perform: kms:CreateGrant"**
- **Cause**: KMS key policy doesn't allow CloudWatch Logs service
- **Solution**: Verify the key policy includes the CloudWatch Logs service principal with required permissions

**Error: "Invalid KMS key"**
- **Cause**: KMS key is in a different region than the log groups
- **Solution**: Create the KMS key in the same region as your ECS service

**Error: "Access denied"**
- **Cause**: Missing encryption context condition in key policy
- **Solution**: Ensure the key policy includes the `kms:EncryptionContext:aws:logs:arn` condition

### Cost Considerations

**KMS Key Costs:**
- Customer-managed key: $1/month
- KMS API requests: $0.03 per 10,000 requests
- Typical cost for ECS logging: $1-2/month additional

**Example Monthly Costs:**
- KMS key: $1.00
- Log ingestion (1GB/day): $15.00
- Log storage (30GB): $1.50
- KMS API requests: $0.10
- **Total: ~$17.60/month with KMS encryption** (vs $16.50 without)

### Security Best Practices

1. **Enable Key Rotation**: Set `enable_key_rotation = true` for automatic annual rotation
2. **Restrict Key Access**: Use key policies to limit who can use or manage the key
3. **Monitor Key Usage**: Enable CloudTrail to log all KMS key operations
4. **Use Separate Keys**: Consider separate KMS keys for different environments (dev/staging/prod)
5. **Backup Key Policy**: Document your key policy configuration for disaster recovery

---

## IAM Permissions and Security

### ECS Instance Permissions

This module uses the AWS-managed policy **`AmazonEC2ContainerServiceforEC2Role`** for ECS instance permissions. This policy is automatically maintained by AWS and includes all necessary permissions for ECS container instances to function properly.

**Benefits:**
- ✅ **Automatically updated** - AWS maintains the policy when ECS requirements change
- ✅ **Best practices** - Follows AWS recommendations for ECS instance roles
- ✅ **No maintenance needed** - No action required when AWS updates ECS features
- ✅ **Minimal permissions** - Only includes necessary ECS and EC2 describe permissions

**What's Included:**
The AWS-managed policy grants permissions for:
- ECS cluster registration and deregistration
- ECS task lifecycle management
- EC2 instance metadata access
- CloudWatch metrics and logs (when enabled)

**Additional Permissions:**
The module adds a minimal custom policy on top of the AWS-managed policy for:
- CloudWatch Logs write permissions (when `enable_cloudwatch_logs = true`)
- Any extra policies specified via `execution_extra_policy` variable

**Security Note:**
The module follows the principle of least privilege. No wildcard permissions (like `ecs:*` or `ec2:Describe*`) are used in custom policies. All broad permissions are delegated to the AWS-managed policy, which AWS maintains responsibly.

---

## Migration from Amazon Linux 2 to Amazon Linux 2023

**Breaking Change (v6.0.0+):** This module now defaults to Amazon Linux 2023 (AL2023) ECS-optimized AMIs instead of Amazon Linux 2.

### What Changed
- Default AMI filter changed from `amzn2-ami-ecs-hvm-*` to `al2023-ami-ecs-hvm-*`
- This affects all new ECS instances launched by the autoscaling group

### Migration Path

**Option 1: Stay on Amazon Linux 2 (Recommended for existing deployments)**
If you want to continue using Amazon Linux 2, explicitly set the `ami_id` variable:
```hcl
module "httpd" {
  source  = "infrahouse/ecs/aws"
  version = "7.0.0"
  ami_id  = "<your-al2-ami-id>"  # Lock to Amazon Linux 2
  # ... other configuration
}
```

**Option 2: Migrate to Amazon Linux 2023**
To adopt AL2023, simply upgrade the module version. Note that existing instances will need to be replaced:
1. The autoscaling group will gradually replace instances with AL2023-based ones
2. During replacement, ECS tasks will be migrated to new instances
3. Test thoroughly in a non-production environment first

### Key Differences
- AL2023 uses systemd-based initialization (cloud-init still supported)
- Different default package versions
- Improved security posture and longer support lifecycle
- See [AWS AL2023 documentation](https://docs.aws.amazon.com/linux/al2023/ug/compare-with-al2.html) for detailed differences

### Custom AMIs
If you use custom AMIs based on Amazon Linux 2, you must:
- Rebuild your AMIs based on AL2023, OR
- Explicitly set the `ami_id` variable to your custom AL2 AMI

```hcl
module "httpd" {
  source  = "infrahouse/ecs/aws"
  version = "7.0.0"
  providers = {
    aws     = aws
    aws.dns = aws
  }
  load_balancer_subnets         = module.service-network.subnet_public_ids
  asg_subnets                   = module.service-network.subnet_private_ids
  dns_names                     = ["foo-ecs"]
  docker_image                  = "httpd"
  container_port                = 80
  service_name                  = var.service_name
  ssh_key_name                  = aws_key_pair.test.key_name
  zone_id                       = data.aws_route53_zone.cicd.zone_id
  internet_gateway_id           = module.service-network.internet_gateway_id
}
```

### Mount EFS volume

The module can attach one or more EFS volumes to a container.

To do that, create the EFS volume with a mount point:
```hcl
resource "aws_efs_file_system" "my-volume" {
  creation_token = "my-volume"
  tags = {
    Name = "my-volume"
  }
}

resource "aws_efs_mount_target" "my-volume" {
  for_each       = toset(var.subnet_private_ids)
  file_system_id = aws_efs_file_system.my-volume.id
  subnet_id      = each.key
}
```

Pass the volumes to the ECS module:
```hcl
module "httpd" {
  source  = "infrahouse/ecs/aws"
  version = "7.0.0"
  providers = {
    aws     = aws
    aws.dns = aws
  }
...
  task_volumes = {
    "my-volume" : {
      file_system_id : aws_efs_file_system.my-volume.id
      container_path : "/mnt/"
    }
}
```

## Variable Validations

This module includes built-in validations to catch configuration errors early.

**Note:** This module requires **Terraform >= 1.5.0** due to the use of `check` blocks for cross-variable validation. If you're using an older version of Terraform, you'll see an error during `terraform init`.

### Input Variable Validations

- **`lb_type`**: Must be either `"alb"` or `"nlb"` (case-insensitive)
- **`container_port`**: Must be between 1 and 65535
- **`autoscaling_metric`**: Must be one of:
  - `ECSServiceAverageCPUUtilization`
  - `ECSServiceAverageMemoryUtilization`
  - `ALBRequestCountPerTarget`
- **`cloudwatch_log_group_retention`**: Must be a valid CloudWatch retention period (0, 1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, or 3653 days)

### Cross-Variable Validations

The module uses Terraform check blocks (in `validations.tf`) to validate relationships between variables:

- **Health Check Configuration**: `healthcheck_interval` must be greater than or equal to `healthcheck_timeout`

If you encounter validation errors during `terraform plan`, the error message will guide you to fix the configuration issue.

<!-- BEGIN_TF_DOCS -->

## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | ~> 1.5 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 5.56, < 7.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | 5.65.0 |
| <a name="provider_aws.dns"></a> [aws.dns](#provider\_aws.dns) | 5.65.0 |
| <a name="provider_cloudinit"></a> [cloudinit](#provider\_cloudinit) | 2.3.4 |
| <a name="provider_tls"></a> [tls](#provider\_tls) | 4.1.0 |

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_pod"></a> [pod](#module\_pod) | registry.infrahouse.com/infrahouse/website-pod/aws | 5.12.1 |
| <a name="module_tcp-pod"></a> [tcp-pod](#module\_tcp-pod) | registry.infrahouse.com/infrahouse/tcp-pod/aws | 0.6.0 |

## Resources

| Name | Type |
|------|------|
| [aws_appautoscaling_policy.ecs_policy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/appautoscaling_policy) | resource |
| [aws_appautoscaling_target.ecs_target](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/appautoscaling_target) | resource |
| [aws_cloudwatch_event_rule.failed_deployment_event_rule](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_event_rule) | resource |
| [aws_cloudwatch_event_target.ecs_task_deployment_failure_sns](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_event_target) | resource |
| [aws_cloudwatch_log_group.ecs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group) | resource |
| [aws_cloudwatch_log_group.ecs_ec2_dmesg](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group) | resource |
| [aws_cloudwatch_log_group.ecs_ec2_syslog](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group) | resource |
| [aws_ecs_capacity_provider.ecs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecs_capacity_provider) | resource |
| [aws_ecs_cluster.ecs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecs_cluster) | resource |
| [aws_ecs_cluster_capacity_providers.ecs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecs_cluster_capacity_providers) | resource |
| [aws_ecs_service.cloudwatch_agent_service](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecs_service) | resource |
| [aws_ecs_service.ecs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecs_service) | resource |
| [aws_ecs_task_definition.cloudwatch_agent](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecs_task_definition) | resource |
| [aws_ecs_task_definition.ecs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecs_task_definition) | resource |
| [aws_iam_policy.ecs_task_execution_logs_policy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy) | resource |
| [aws_iam_role.cloudwatch_agent_execution_role](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role.cloudwatch_agent_task_role](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role.ecs_task_execution_role](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy_attachment.cloudwatch_agent_execution_policy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.cloudwatch_agent_task_policy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.ecs_instance_role](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.ecs_task_execution_role_logs_policy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.ecs_task_execution_role_policy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.execution_extra_policy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.extra_policy_attachment](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_key_pair.ecs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/key_pair) | resource |
| [tls_private_key.rsa](https://registry.terraform.io/providers/hashicorp/tls/latest/docs/resources/private_key) | resource |
| [aws_ami.ecs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/ami) | data source |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_ec2_instance_type.backend](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/ec2_instance_type) | data source |
| [aws_ec2_instance_type.ecs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/ec2_instance_type) | data source |
| [aws_iam_instance_profile.tcp_pod](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_instance_profile) | data source |
| [aws_iam_policy.ecs-task-execution-role-policy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy) | data source |
| [aws_iam_policy_document.assume_role_policy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.cloudwatch_agent_task_role_assume_policy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.ecs_cloudwatch_logs_policy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.instance_policy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_internet_gateway.default](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/internet_gateway) | data source |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |
| [aws_route53_zone.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/route53_zone) | data source |
| [aws_subnet.load_balancer](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/subnet) | data source |
| [aws_subnet.selected](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/subnet) | data source |
| [cloudinit_config.ecs](https://registry.terraform.io/providers/hashicorp/cloudinit/latest/docs/data-sources/config) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_access_log_force_destroy"></a> [access\_log\_force\_destroy](#input\_access\_log\_force\_destroy) | Destroy S3 bucket with access logs even if non-empty | `bool` | `false` | no |
| <a name="input_alarm_emails"></a> [alarm\_emails](#input\_alarm\_emails) | List of email addresses to receive CloudWatch alarm notifications.<br/>Required for monitoring ECS service health and performance issues.<br/><br/>Example: ["devops@example.com", "oncall@example.com"] | `list(string)` | n/a | yes |
| <a name="input_ami_id"></a> [ami\_id](#input\_ami\_id) | Image for host EC2 instances.<br/>If not specified, the latest Amazon Linux 2023 ECS-optimized image will be used. | `string` | `null` | no |
| <a name="input_asg_health_check_grace_period"></a> [asg\_health\_check\_grace\_period](#input\_asg\_health\_check\_grace\_period) | ASG will wait up to this number of seconds for instance to become healthy.<br/>Default: 300 seconds (5 minutes) | `number` | `300` | no |
| <a name="input_asg_instance_type"></a> [asg\_instance\_type](#input\_asg\_instance\_type) | EC2 instances type | `string` | `"t3.micro"` | no |
| <a name="input_asg_max_size"></a> [asg\_max\_size](#input\_asg\_max\_size) | Maximum number of instances in ASG.<br/>Default: Automatically calculated based on number of tasks and their memory requirements. | `number` | `null` | no |
| <a name="input_asg_min_size"></a> [asg\_min\_size](#input\_asg\_min\_size) | Minimum number of instances in ASG.<br/>Default: The number of subnets (one instance per subnet for high availability). | `number` | `null` | no |
| <a name="input_asg_subnets"></a> [asg\_subnets](#input\_asg\_subnets) | Auto Scaling Group Subnets. | `list(string)` | n/a | yes |
| <a name="input_assume_dns"></a> [assume\_dns](#input\_assume\_dns) | If true, create DNS records provided by var.dns\_names.<br/>Set to false if DNS records are managed externally. | `bool` | `true` | no |
| <a name="input_autoscaling_metric"></a> [autoscaling\_metric](#input\_autoscaling\_metric) | Metric to base autoscaling on.<br/><br/>Valid values:<br/>- "ECSServiceAverageCPUUtilization" (default) - Scale based on CPU usage<br/>- "ECSServiceAverageMemoryUtilization" - Scale based on memory usage<br/>- "ALBRequestCountPerTarget" - Scale based on ALB requests per target | `string` | `"ECSServiceAverageCPUUtilization"` | no |
| <a name="input_autoscaling_target"></a> [autoscaling\_target](#input\_autoscaling\_target) | Target value for autoscaling\_metric. | `number` | `null` | no |
| <a name="input_autoscaling_target_cpu_usage"></a> [autoscaling\_target\_cpu\_usage](#input\_autoscaling\_target\_cpu\_usage) | Target CPU utilization percentage for autoscaling.<br/>Only used when autoscaling\_metric is "ECSServiceAverageCPUUtilization".<br/><br/>ECS will scale in/out to maintain this CPU usage level.<br/>Default: 60% (matches website-pod default for consistency) | `number` | `60` | no |
| <a name="input_certificate_issuers"></a> [certificate\_issuers](#input\_certificate\_issuers) | List of certificate authority domains allowed to issue certificates for this domain (e.g., ["amazon.com", "letsencrypt.org"]).<br/>The module will format these as CAA records. | `list(string)` | <pre>[<br/>  "amazon.com"<br/>]</pre> | no |
| <a name="input_cloudinit_extra_commands"></a> [cloudinit\_extra\_commands](#input\_cloudinit\_extra\_commands) | Extra commands for run on ASG. | `list(string)` | `[]` | no |
| <a name="input_cloudwatch_agent_image"></a> [cloudwatch\_agent\_image](#input\_cloudwatch\_agent\_image) | CloudWatch agent container image.<br/><br/>Default is pinned to a specific version for stability and reproducibility.<br/>Pinned versions prevent unexpected breaking changes when AWS updates the agent.<br/><br/>You can override this to use ":latest" if you want automatic updates,<br/>though this is not recommended for production environments.<br/><br/>Version Selection:<br/>- Current version (1.300062.0b1304) was the latest stable release at time of pinning<br/>- Verified to work with Amazon Linux 2023 and ECS<br/>- No known security vulnerabilities at time of selection<br/><br/>Updating the Version:<br/>1. Check available versions: https://gallery.ecr.aws/cloudwatch-agent/cloudwatch-agent<br/>2. Review AWS CloudWatch Agent release notes for breaking changes<br/>3. Test in non-production environment first<br/>4. Override this variable with the new version:<br/>   cloudwatch\_agent\_image = "public.ecr.aws/cloudwatch-agent/cloudwatch-agent:NEW\_VERSION"<br/><br/>Security Monitoring:<br/>- Monitor AWS security bulletins: https://aws.amazon.com/security/security-bulletins/<br/>- Subscribe to CloudWatch Agent GitHub releases: https://github.com/aws/amazon-cloudwatch-agent<br/>- Consider automated container vulnerability scanning (e.g., AWS ECR scanning, Trivy) | `string` | `"public.ecr.aws/cloudwatch-agent/cloudwatch-agent:1.300062.0b1304"` | no |
| <a name="input_cloudwatch_log_group"></a> [cloudwatch\_log\_group](#input\_cloudwatch\_log\_group) | CloudWatch log group name to create and use.<br/>Default: /ecs/{var.environment}/{var.service\_name}<br/><br/>Example: If environment="production" and service\_name="api",<br/>the log group will be "/ecs/production/api" | `string` | `null` | no |
| <a name="input_cloudwatch_log_group_retention"></a> [cloudwatch\_log\_group\_retention](#input\_cloudwatch\_log\_group\_retention) | Number of days you want to retain log events in the log group. | `number` | `365` | no |
| <a name="input_cloudwatch_log_kms_key_id"></a> [cloudwatch\_log\_kms\_key\_id](#input\_cloudwatch\_log\_kms\_key\_id) | KMS key ID (ARN) to encrypt CloudWatch logs.<br/><br/>If not specified, logs will use AWS managed encryption.<br/>For enhanced security and compliance, provide a customer-managed KMS key.<br/><br/>Example: "arn:aws:kms:us-east-1:123456789012:key/12345678-1234-1234-1234-123456789012" | `string` | `null` | no |
| <a name="input_container_command"></a> [container\_command](#input\_container\_command) | If specified, use this list of strings as a docker command. | `list(string)` | `null` | no |
| <a name="input_container_cpu"></a> [container\_cpu](#input\_container\_cpu) | Number of CPU units that a container is going to use. | `number` | `200` | no |
| <a name="input_container_healthcheck_command"></a> [container\_healthcheck\_command](#input\_container\_healthcheck\_command) | A shell command that a container runs to check if it's healthy. Exit code 0 means healthy, non-zero - unhealthy. | `string` | `"curl -f http://localhost/ || exit 1"` | no |
| <a name="input_container_memory"></a> [container\_memory](#input\_container\_memory) | Amount of RAM in megabytes the container is going to use. | `number` | `128` | no |
| <a name="input_container_port"></a> [container\_port](#input\_container\_port) | TCP port that a container serves client requests on. | `number` | `8080` | no |
| <a name="input_dns_names"></a> [dns\_names](#input\_dns\_names) | List of hostnames the module will create in var.zone\_id. | `list(string)` | n/a | yes |
| <a name="input_dockerSecurityOptions"></a> [dockerSecurityOptions](#input\_dockerSecurityOptions) | A list of strings to provide custom configuration for multiple security systems.<br/><br/>Supported options:<br/>- "no-new-privileges" - Prevent privilege escalation<br/>- "label:<value>" - SELinux labels<br/>- "apparmor:<value>" - AppArmor profile<br/>- "credentialspec:<value>" - Credential specifications (Windows)<br/><br/>Example:<br/>  dockerSecurityOptions = [<br/>    "no-new-privileges",<br/>    "label:type:container\_runtime\_t"<br/>  ] | `list(string)` | `null` | no |
| <a name="input_docker_image"></a> [docker\_image](#input\_docker\_image) | A container image that will run the service. | `string` | n/a | yes |
| <a name="input_enable_cloudwatch_logs"></a> [enable\_cloudwatch\_logs](#input\_enable\_cloudwatch\_logs) | Enable CloudWatch Logs for ECS tasks.<br/>If enabled, containers will use "awslogs" log driver.<br/><br/>Default: true (recommended for production environments) | `bool` | `true` | no |
| <a name="input_enable_container_insights"></a> [enable\_container\_insights](#input\_enable\_container\_insights) | Enable container insights feature on ECS cluster. | `bool` | `false` | no |
| <a name="input_enable_deployment_circuit_breaker"></a> [enable\_deployment\_circuit\_breaker](#input\_enable\_deployment\_circuit\_breaker) | Enable ECS deployment circuit breaker. | `bool` | `true` | no |
| <a name="input_environment"></a> [environment](#input\_environment) | Name of environment. | `string` | `"development"` | no |
| <a name="input_execution_extra_policy"></a> [execution\_extra\_policy](#input\_execution\_extra\_policy) | A map of extra policies attached to the task execution role.<br/>The task execution role is used by the ECS agent to pull images, write logs, and access secrets.<br/><br/>Key: Arbitrary identifier (e.g., "secrets\_access")<br/>Value: IAM policy ARN<br/><br/>Example:<br/>  execution\_extra\_policy = {<br/>    "secrets\_access" = "arn:aws:iam::123456789012:policy/ECSSecretsAccess"<br/>    "ecr\_pull"       = "arn:aws:iam::123456789012:policy/ECRPullPolicy"<br/>  } | `map(string)` | `{}` | no |
| <a name="input_execution_task_role_policy_arn"></a> [execution\_task\_role\_policy\_arn](#input\_execution\_task\_role\_policy\_arn) | Extra policy for execution task role. | `string` | `null` | no |
| <a name="input_extra_files"></a> [extra\_files](#input\_extra\_files) | Additional files to create on a host EC2 instance. | <pre>list(<br/>    object(<br/>      {<br/>        content     = string<br/>        path        = string<br/>        permissions = string<br/>      }<br/>    )<br/>  )</pre> | `[]` | no |
| <a name="input_extra_instance_profile_permissions"></a> [extra\_instance\_profile\_permissions](#input\_extra\_instance\_profile\_permissions) | A JSON with a permissions policy document. The policy will be attached to the ASG instance profile. | `string` | `null` | no |
| <a name="input_healthcheck_interval"></a> [healthcheck\_interval](#input\_healthcheck\_interval) | Number of seconds between checks | `number` | `10` | no |
| <a name="input_healthcheck_path"></a> [healthcheck\_path](#input\_healthcheck\_path) | Path on the webserver that the elb will check to determine whether the instance is healthy or not. | `string` | `"/index.html"` | no |
| <a name="input_healthcheck_response_code_matcher"></a> [healthcheck\_response\_code\_matcher](#input\_healthcheck\_response\_code\_matcher) | Range of http return codes that can match | `string` | `"200-299"` | no |
| <a name="input_healthcheck_timeout"></a> [healthcheck\_timeout](#input\_healthcheck\_timeout) | Healthcheck timeout | `number` | `5` | no |
| <a name="input_idle_timeout"></a> [idle\_timeout](#input\_idle\_timeout) | The time in seconds that the connection is allowed to be idle. | `number` | `60` | no |
| <a name="input_lb_type"></a> [lb\_type](#input\_lb\_type) | Load balancer type. ALB or NLB | `string` | `"alb"` | no |
| <a name="input_load_balancer_subnets"></a> [load\_balancer\_subnets](#input\_load\_balancer\_subnets) | Load Balancer Subnets. | `list(string)` | n/a | yes |
| <a name="input_managed_draining"></a> [managed\_draining](#input\_managed\_draining) | Enables or disables a graceful shutdown of instances without disturbing workloads. | `bool` | `true` | no |
| <a name="input_managed_termination_protection"></a> [managed\_termination\_protection](#input\_managed\_termination\_protection) | Enables or disables container-aware termination of instances in the auto scaling group when scale-in happens. | `bool` | `true` | no |
| <a name="input_on_demand_base_capacity"></a> [on\_demand\_base\_capacity](#input\_on\_demand\_base\_capacity) | If specified, the ASG will request spot instances and this will be the minimal number of on-demand instances. | `number` | `null` | no |
| <a name="input_root_volume_size"></a> [root\_volume\_size](#input\_root\_volume\_size) | Root volume size in EC2 instance in Gigabytes | `number` | `30` | no |
| <a name="input_service_health_check_grace_period_seconds"></a> [service\_health\_check\_grace\_period\_seconds](#input\_service\_health\_check\_grace\_period\_seconds) | Seconds to ignore failing load balancer health checks on newly instantiated tasks.<br/>This prevents ECS from killing tasks that are still starting up.<br/><br/>Use this when:<br/>- Your application takes time to initialize (e.g., loading data, warming caches)<br/>- Health checks fail during the startup period<br/>- You see tasks being killed and restarted repeatedly<br/><br/>Default: null (uses ECS default behavior)<br/>Range: 0 to 2147483647 seconds<br/><br/>Example: 300 (5 minutes grace period for slow-starting applications) | `number` | `null` | no |
| <a name="input_service_name"></a> [service\_name](#input\_service\_name) | Service name | `string` | n/a | yes |
| <a name="input_sns_topic_arn"></a> [sns\_topic\_arn](#input\_sns\_topic\_arn) | SNS topic arn for sending alerts on failed deployments. | `string` | `null` | no |
| <a name="input_ssh_cidr_block"></a> [ssh\_cidr\_block](#input\_ssh\_cidr\_block) | CIDR range that is allowed to SSH into the backend instances | `string` | `null` | no |
| <a name="input_ssh_key_name"></a> [ssh\_key\_name](#input\_ssh\_key\_name) | ssh key name installed in ECS host instances. | `string` | `null` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags to apply to resources creatded by the module. | `map(string)` | `{}` | no |
| <a name="input_task_desired_count"></a> [task\_desired\_count](#input\_task\_desired\_count) | Number of containers the ECS service will maintain. | `number` | `1` | no |
| <a name="input_task_efs_volumes"></a> [task\_efs\_volumes](#input\_task\_efs\_volumes) | Map name->{file\_system\_id, container\_path} of EFS volumes defined in task and available for containers to mount. | <pre>map(<br/>    object(<br/>      {<br/>        file_system_id : string<br/>        container_path : string<br/>      }<br/>    )<br/>  )</pre> | `{}` | no |
| <a name="input_task_environment_variables"></a> [task\_environment\_variables](#input\_task\_environment\_variables) | Environment variables passed down to a task. | <pre>list(<br/>    object(<br/>      {<br/>        name : string<br/>        value : string<br/>      }<br/>    )<br/>  )</pre> | `[]` | no |
| <a name="input_task_ipc_mode"></a> [task\_ipc\_mode](#input\_task\_ipc\_mode) | The IPC resource namespace to use for the containers in the task.<br/>Controls how containers share inter-process communication resources.<br/><br/>Valid values:<br/>- null (default) - Each container has its own private IPC namespace<br/>- "host" - Containers use the host's IPC namespace (use with caution)<br/>- "task" - All containers in the task share the same IPC namespace<br/>- "none" - IPC namespace is disabled<br/><br/>Use "task" when:<br/>- Containers need to communicate via shared memory<br/>- Running multi-container applications that use IPC (e.g., sidecars with shared memory)<br/><br/>Reference: https://docs.aws.amazon.com/AmazonECS/latest/APIReference/API_TaskDefinition.html | `string` | `null` | no |
| <a name="input_task_local_volumes"></a> [task\_local\_volumes](#input\_task\_local\_volumes) | Map name->{host\_path, container\_path} of local volumes defined in task and available for containers to mount. | <pre>map(<br/>    object(<br/>      {<br/>        host_path : string<br/>        container_path : string<br/>      }<br/>    )<br/>  )</pre> | `{}` | no |
| <a name="input_task_max_count"></a> [task\_max\_count](#input\_task\_max\_count) | Highest number of tasks to run | `number` | `10` | no |
| <a name="input_task_min_count"></a> [task\_min\_count](#input\_task\_min\_count) | Lowest number of tasks to run | `number` | `1` | no |
| <a name="input_task_role_arn"></a> [task\_role\_arn](#input\_task\_role\_arn) | Task Role ARN. The role will be assumed by a container. | `string` | `null` | no |
| <a name="input_task_secrets"></a> [task\_secrets](#input\_task\_secrets) | Secrets to pass to a container. A `name` will be the environment variable. valueFrom is a secret ARN. | <pre>list(<br/>    object(<br/>      {<br/>        name : string<br/>        valueFrom : string<br/>      }<br/>    )<br/>  )</pre> | `[]` | no |
| <a name="input_upstream_module"></a> [upstream\_module](#input\_upstream\_module) | Module that called this module. | `string` | `null` | no |
| <a name="input_users"></a> [users](#input\_users) | A list of maps with user definitions according to the cloud-init format | `any` | `null` | no |
| <a name="input_vanta_contains_ephi"></a> [vanta\_contains\_ephi](#input\_vanta\_contains\_ephi) | This tag allows administrators to define whether or not a resource contains<br/>electronically Protected Health Information (ePHI).<br/><br/>Set to true if the resource contains ePHI, false otherwise.<br/>Used for HIPAA compliance tracking in Vanta. | `bool` | `false` | no |
| <a name="input_vanta_contains_user_data"></a> [vanta\_contains\_user\_data](#input\_vanta\_contains\_user\_data) | This tag allows administrators to define whether or not a resource contains user data.<br/><br/>Set to true if the resource contains user data, false otherwise.<br/>Used for Vanta compliance tracking. | `bool` | `false` | no |
| <a name="input_vanta_description"></a> [vanta\_description](#input\_vanta\_description) | This tag allows administrators to set a description, for instance, or add any other descriptive information. | `string` | `null` | no |
| <a name="input_vanta_no_alert"></a> [vanta\_no\_alert](#input\_vanta\_no\_alert) | Mark a resource as out of scope for Vanta audit.<br/><br/>If set, you must provide a reason explaining why the resource<br/>is not relevant to the audit. | `string` | `null` | no |
| <a name="input_vanta_owner"></a> [vanta\_owner](#input\_vanta\_owner) | The email address of the instance's owner for Vanta tracking.<br/><br/>Must be set to the email address of an existing user in Vanta.<br/>If the email doesn't match a Vanta user, no owner will be assigned. | `string` | `null` | no |
| <a name="input_vanta_production_environments"></a> [vanta\_production\_environments](#input\_vanta\_production\_environments) | Environment names to consider production grade in Vanta. | `list(string)` | <pre>[<br/>  "production",<br/>  "prod"<br/>]</pre> | no |
| <a name="input_vanta_user_data_stored"></a> [vanta\_user\_data\_stored](#input\_vanta\_user\_data\_stored) | This tag allows administrators to describe the type of user data the instance contains. | `string` | `null` | no |
| <a name="input_zone_id"></a> [zone\_id](#input\_zone\_id) | Zone where DNS records will be created for the service and certificate validation. | `string` | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_acm_certificate_arn"></a> [acm\_certificate\_arn](#output\_acm\_certificate\_arn) | ARN of the ACM certificate used by the load balancer |
| <a name="output_asg_arn"></a> [asg\_arn](#output\_asg\_arn) | Autoscaling group ARN created for the ECS service. |
| <a name="output_asg_name"></a> [asg\_name](#output\_asg\_name) | Autoscaling group name created for the ECS service. |
| <a name="output_backend_security_group"></a> [backend\_security\_group](#output\_backend\_security\_group) | Security group of backend. |
| <a name="output_cloudwatch_log_group_name"></a> [cloudwatch\_log\_group\_name](#output\_cloudwatch\_log\_group\_name) | Name of the main CloudWatch log group for ECS tasks |
| <a name="output_cloudwatch_log_group_names"></a> [cloudwatch\_log\_group\_names](#output\_cloudwatch\_log\_group\_names) | Names of all CloudWatch log groups created by this module |
| <a name="output_dns_hostnames"></a> [dns\_hostnames](#output\_dns\_hostnames) | DNS hostnames where the ECS service is available. |
| <a name="output_load_balancer_arn"></a> [load\_balancer\_arn](#output\_load\_balancer\_arn) | Load balancer ARN. |
| <a name="output_load_balancer_dns_name"></a> [load\_balancer\_dns\_name](#output\_load\_balancer\_dns\_name) | Load balancer DNS name. |
| <a name="output_load_balancer_security_groups"></a> [load\_balancer\_security\_groups](#output\_load\_balancer\_security\_groups) | Security groups associated with the load balancer |
| <a name="output_service_arn"></a> [service\_arn](#output\_service\_arn) | ECS service ARN. |
| <a name="output_ssl_listener_arn"></a> [ssl\_listener\_arn](#output\_ssl\_listener\_arn) | SSL listener ARN |
| <a name="output_task_execution_role_arn"></a> [task\_execution\_role\_arn](#output\_task\_execution\_role\_arn) | Task execution role is a role that ECS agent gets. |
| <a name="output_task_execution_role_name"></a> [task\_execution\_role\_name](#output\_task\_execution\_role\_name) | Task execution role is a role that ECS agent gets. |
<!-- END_TF_DOCS -->
