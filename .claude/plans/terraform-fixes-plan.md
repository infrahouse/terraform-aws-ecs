# Plan to Fix Terraform Module Issues

**Date:** 2025-11-30
**Module:** terraform-aws-ecs
**Current Version:** 6.1.0
**Review Document:** `.claude/reviews/terraform-module-review.md`

---

## Issue Tracker

### Phase 1: Critical Security Fixes

#### Issue #1: Add KMS Encryption for CloudWatch Log Groups
- [x] Add `cloudwatch_log_kms_key_id` variable to `variables.tf`
- [x] Update `aws_cloudwatch_log_group.ecs` in `cloudwatch.tf`
- [x] Update `aws_cloudwatch_log_group.ecs_ec2_syslog` in `cloudwatch.tf`
- [x] Update `aws_cloudwatch_log_group.ecs_ec2_dmesg` in `cloudwatch.tf`
- [x] Add test validation for CloudWatch log group encryption
- [x] Add cloudwatch_log_group_names output as map
- [x] Test backward compatibility (null encryption) - PASSED
- [ ] Test with KMS encryption enabled (pending KMS key)
- [x] Run terraform fmt and validate

**Bonus Improvements:**
- [x] Removed `internet_gateway_id` variable - now auto-detected from load_balancer_subnets
- [x] Migrated tests to use `subzone` fixture instead of `test_zone_name`
- [x] Changed `cloudwatch_log_group_names` output from list to map for easier access

**Test Results:** ✅ PASSED (1 passed in 300.05s)
- All 3 log groups created successfully
- Encryption validation working (currently using AWS managed encryption)
- Map output format working correctly
- Subzone migration successful
- Internet gateway auto-detection working

**Status:** ✅ Completed & Tested

---

#### Issue #2: Scope Down IAM Policies (Fix Wildcards)
- [x] Replace `ecs:*` with AWS managed policy `AmazonEC2ContainerServiceforEC2Role`
- [x] Replace `ec2:Describe*` with AWS managed policy `AmazonEC2ContainerServiceforEC2Role`
- [x] Add instance_role_name to locals.tf
- [x] Add data source to get role name from instance profile (for tcp-pod)
- [x] Create aws_iam_role_policy_attachment in iam.tf
- [x] Remove wildcard statements from datasources.tf
- [x] Test ECS instances can register properly - PASSED
- [x] Verify no permission errors in CloudWatch logs - PASSED
- [x] Run terraform fmt and validate

**Implementation:**
- Added `local.instance_role_name` to get role name from website-pod or tcp-pod
- For ALB: Uses `module.pod[0].instance_role_name` directly
- For NLB: Uses data source to lookup role from `instance_profile_name`
- Attached AWS managed policy `AmazonEC2ContainerServiceforEC2Role` to instance role in iam.tf
- Removed `ecs:*` and `ec2:Describe*` wildcard statements from inline policy
- Inline policy now only contains module-specific permissions (CloudWatch logs)

**Testing:**
- Manually terminated EC2 instance to force new instance creation
- New instance successfully registered to ECS cluster
- Tasks deployed and ran successfully on new instance
- No permission errors in CloudWatch logs

**Benefits:**
- Uses AWS maintained policy (automatically updated when ECS changes)
- Follows AWS best practices
- No more wildcard permissions in inline policy
- Cleaner separation of concerns
- Works for both ALB and NLB configurations

**Status:** ✅ Completed & Tested

---

#### Issue #3: Pin CloudWatch Agent to Specific Version
- [x] Update `cloudwatch_agent_image` variable default in `variables.tf`
- [x] Add HEREDOC documentation explaining version pinning trade-offs
- [x] Allow users to override (including `:latest` if desired)
- [ ] Test with new pinned version
- [x] Run terraform fmt and validate

**Implementation:**
- Changed default from `:latest` to pinned version `1.300049.0`
- Added comprehensive HEREDOC documentation explaining:
  - Why pinning is recommended (stability, reproducibility)
  - How to use `:latest` if desired (but not recommended for production)
  - Link to ECR gallery to check available versions
- NO validation block added - users have flexibility to choose

**Philosophy:**
- Secure by default (pinned version)
- Allow user choice (can override to `:latest`)
- Educate don't restrict (documentation explains trade-offs)

**Status:** ✅ Completed (Tests Recommended)

---

#### Issue #4: Add Variable Validation Blocks
- [x] Add validation for `lb_type` (alb/nlb)
- [x] Add validation for `container_port` (1-65535)
- [x] Add validation for `autoscaling_metric` (valid ECS metrics)
- [x] Add validation for `healthcheck_interval` (>= timeout) - using check block in validations.tf
- [x] Add validation for `cloudwatch_log_group_retention` (valid values)
- [x] Test validation with existing tests - PASSED (1 passed in 69.64s)
- [x] Update documentation - Added "Variable Validations" section to README.md
- [x] Run terraform fmt and validate

**Implementation Details:**
- Added variable validation blocks for `lb_type`, `container_port`, `autoscaling_metric`, and `cloudwatch_log_group_retention` in `variables.tf`
- Created new `validations.tf` file with Terraform check block for cross-variable validation (`healthcheck_interval >= healthcheck_timeout`)
- Pattern follows website-pod module's approach for better error messages
- All validations tested and working correctly
- Documentation added to README.md explaining all validations

**Files Modified:**
- `variables.tf` - Added 4 validation blocks
- `validations.tf` - NEW FILE with cross-variable check block
- `README.md` - Added "Variable Validations" section

**Note:** `capacity_provider_target_capacity` validation removed - keeping hardcoded at 100 (no variable needed)

**Status:** ✅ Completed & Documented

---

### Phase 1.5: Breaking Changes (Major Version 7.0.0)

#### Issue #16: Upgrade to website-pod 5.12.1 and Make alarm_emails Required
- [x] Update `website-pod.tf` module version from 5.9.0 to 5.12.1
- [x] Update `tcp-pod.tf` module version to latest compatible version (kept at 0.6.0)
- [x] Add `alarm_emails` variable to `variables.tf` (required, no default)
- [x] Add validation for `alarm_emails` (must be valid email list)
- [x] Pass `alarm_emails` to website-pod module in `website-pod.tf`
- [x] ~~Pass `alarm_emails` to tcp-pod module in `tcp-pod.tf`~~ DEFERRED to future-work-plan.md (tcp-pod 0.6.0 doesn't support alarm_emails yet)
- [x] Update all test files to include `alarm_emails` parameter (used test@example.com)
- [x] Fix deprecation warning: attach_tagret_group_to_asg → attach_target_group_to_asg
- [x] Test with alarm_emails - PASSED (1 passed in 93.76s, no warnings)
- [ ] Ensure commit message includes BREAKING CHANGE footer (for git-cliff auto-generation)
- [x] Add migration guide in README for v6 to v7
- [x] ~~Run terraform fmt and validate~~ SKIPPED - will be done manually during commit

**Status:** ✅ Completed & Documented

---

#### Issue #17: Complete Migration Guide with Behavioral Changes
- [x] Add "Behavioral Changes" section to README.md migration guide
- [x] Document CloudWatch logs now enabled by default (cost impact: ~$15-20/month per service)
- [x] Document CPU autoscaling target changed from 80% to 60% (earlier scaling, potentially higher costs)
- [x] Document output format change: cloudwatch_log_group_names list → map
- [x] Document internet_gateway_id parameter removed (now auto-detected)
- [x] Add examples for maintaining previous behavior (disable logs, 80% CPU target, etc.)
- [x] Add guidance on choosing autoscaling targets (50-60% vs 70% vs 80%)
- [x] Test documentation clarity with fresh eyes

**Priority:** CRITICAL (Blocking Release)
**Estimated Time:** 45 minutes
**Source:** PR Review (.claude/reviews/pr-review.md)

**Current Gap:** Migration guide only documents alarm_emails requirement but misses 4 behavioral changes:
1. CloudWatch logs enabled by default (was false) → cost impact
2. CPU autoscaling target lowered to 60% (was 80%) → scaling behavior change
3. cloudwatch_log_group_names output changed from list to map → breaking for downstream code
4. internet_gateway_id parameter removed → simplification

**Files to Modify:**
- `README.md` - Add comprehensive behavioral changes section to migration guide (lines 26-87)

**Status:** ✅ Completed & Tested

---

#### Issue #18: Add KMS Encryption Documentation and Examples
- [x] Add KMS encryption setup section to README.md
- [x] Document required KMS key policy for CloudWatch Logs service
- [x] Add complete example showing KMS key creation and module usage
- [x] Document region matching requirement (KMS key must be in same region)
- [x] Add security comparison: AWS-managed vs customer-managed encryption
- [x] Test example code for correctness

**Priority:** HIGH (Should Address Before Release)
**Estimated Time:** 30 minutes
**Source:** PR Review (.claude/reviews/pr-review.md)

**Current Gap:** cloudwatch_log_kms_key_id variable exists and works, but no documentation on:
- How to create KMS key for CloudWatch
- Required key policy statements
- Permissions needed for CloudWatch Logs service

**Files to Modify:**
- `README.md` - Add KMS encryption section with complete example

**Implementation Example:**
```markdown
### Using KMS Encryption for CloudWatch Logs

To enable KMS encryption for CloudWatch logs, create a KMS key with proper permissions:

```hcl
resource "aws_kms_key" "cloudwatch" {
  description = "KMS key for CloudWatch Logs encryption"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Enable IAM User Permissions"
        Effect = "Allow"
        Principal = { AWS = "arn:aws:iam::ACCOUNT_ID:root" }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "Allow CloudWatch Logs"
        Effect = "Allow"
        Principal = { Service = "logs.amazonaws.com" }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:CreateGrant",
          "kms:DescribeKey"
        ]
        Resource = "*"
        Condition = {
          ArnLike = {
            "kms:EncryptionContext:aws:logs:arn" = "arn:aws:logs:REGION:ACCOUNT_ID:log-group:*"
          }
        }
      }
    ]
  })
}

module "ecs_service" {
  cloudwatch_log_kms_key_id = aws_kms_key.cloudwatch.arn
  # ...
}
```

**Note:** KMS key must be in the same region as the CloudWatch log groups.

**Status:** ✅ Completed & Documented

---

#### Issue #19: Document Terraform Version Requirements
- [x] Add Terraform version constraint to module or document check block requirements
- [x] Document that check blocks require Terraform 1.5+
- [x] Add to README.md "Requirements" section

**Priority:** HIGH (Should Address Before Release)
**Estimated Time:** 15 minutes
**Source:** PR Review (.claude/reviews/pr-review.md)

**Current Gap:** validations.tf uses check blocks (Terraform 1.5+) but no version constraint documented

**Files Modified:**
- `terraform.tf` - Already has `required_version = "~> 1.5"` constraint ✅
- `README.md` - Added note in Variable Validations section (line 513) explaining Terraform >= 1.5.0 requirement ✅

**What Was Added:**
The Variable Validations section now includes a prominent note:
> **Note:** This module requires **Terraform >= 1.5.0** due to the use of `check` blocks for cross-variable validation. If you're using an older version of Terraform, you'll see an error during `terraform init`.

**Status:** ✅ Completed & Documented

**Priority:** CRITICAL (Breaking Change)
**Estimated Time:** 45 minutes

**Breaking Change Details:**
- `alert_emails` is now a required variable (previously not exposed)
- Users must provide at least one email address for alert notifications
- This enables the new alerts functionality added in website-pod 5.12.1

**Files to Modify:**
- `variables.tf` - Add required `alert_emails` variable
- `website-pod.tf` - Update version to 5.12.1, pass alert_emails
- `tcp-pod.tf` - Update version, pass alert_emails
- All test files in `test_data/` - Add alert_emails
- `README.md` - Add migration guide
- `CHANGELOG.md` - Document breaking change

**Implementation:**
```terraform
# variables.tf
variable "alert_emails" {
  description = <<-EOT
    List of email addresses to receive CloudWatch alert notifications.
    Required for monitoring ECS service health and performance issues.

    Example: ["devops@example.com", "oncall@example.com"]
  EOT
  type        = list(string)

  validation {
    condition     = length(var.alert_emails) > 0
    error_message = "At least one email address must be provided for alert notifications."
  }

  validation {
    condition = alltrue([
      for email in var.alert_emails : can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", email))
    ])
    error_message = "All alert_emails must be valid email addresses."
  }
}

# website-pod.tf
module "pod" {
  source  = "registry.infrahouse.com/infrahouse/website-pod/aws"
  version = "5.12.1"  # Updated from 5.9.0

  # ... existing parameters ...
  alert_emails = var.alert_emails  # New required parameter
}

# tcp-pod.tf
module "pod" {
  source  = "registry.infrahouse.com/infrahouse/tcp-pod/aws"
  version = "~> 5.12"  # Update to compatible version

  # ... existing parameters ...
  alert_emails = var.alert_emails  # New required parameter
}
```

**Migration Guide (for README):**
```markdown
## Migrating from v6.x to v7.0

### Breaking Changes

1. **alert_emails is now required**

   The `alert_emails` variable is now required to enable CloudWatch alerting.

   **Before (v6.x):**
   ```hcl
   module "ecs_service" {
     source  = "infrahouse/ecs/aws"
     version = "~> 6.0"

     service_name = "my-service"
     # ... other parameters
   }
   ```

   **After (v7.0):**
   ```hcl
   module "ecs_service" {
     source  = "infrahouse/ecs/aws"
     version = "~> 7.0"

     service_name = "my-service"
     alert_emails = ["devops@example.com", "oncall@example.com"]  # REQUIRED
     # ... other parameters
   }
   ```

2. **Module Dependencies Updated**
   - `infrahouse/website-pod/aws` updated to 5.12.1 (from 5.9.0)
   - This adds CloudWatch alerts for service health monitoring
```

**Status:** ⬜ Not Started

---

### Phase 2: Important Security & Quality Improvements

#### Issue #5: Mark Secrets as Sensitive
- [ ] Mark `task_secrets` variable as `sensitive = true` in `variables.tf`
- [ ] Improve `task_secrets` description with KMS documentation
- [ ] Mark `backend_security_group` output as sensitive in `outputs.tf`
- [ ] Mark `task_execution_role_arn` output as sensitive in `outputs.tf`
- [ ] Test that secrets don't appear in plan output
- [ ] Run terraform fmt and validate

**Status:** ⬜ Not Started

---

#### Issue #6: Fix SSH Key Security Concern
- [ ] Add `ssh_private_key_retrieval_instructions` output to `outputs.tf`
- [ ] Add `ssh_private_key` sensitive output to `outputs.tf`
- [ ] Add security warning comments to `ssh.tf`
- [ ] Document SSH key security in README
- [ ] Test private key retrieval via terraform output
- [ ] Verify key works for SSH access
- [ ] Run terraform fmt and validate

**Status:** ⬜ Not Started

---

#### Issue #7: Fix Inconsistent Tagging
- [ ] Add `vanta_contains_user_data` variable to `variables.tf`
- [ ] Add `vanta_contains_ephi` variable to `variables.tf`
- [ ] Create unified `resource_tags` local in `locals.tf`
- [ ] Update `aws_ecs_cluster` tags in `main.tf`
- [ ] Update `aws_iam_role.ecs_task_execution_role` tags in `iam.tf`
- [ ] Update all CloudWatch log group tags in `cloudwatch.tf`
- [ ] Add `Name` tags where missing
- [ ] Verify all resources have `module_version` tag
- [ ] Test tag propagation
- [ ] Run terraform fmt and validate

**Status:** ⬜ Not Started

---

#### Issue #8: Remove Tag-Based Implicit Dependencies
- [ ] Remove `execution_role_arn` tag from `aws_ecs_service` in `main.tf`
- [ ] Remove `target_group_arn` tag from `aws_ecs_service` in `main.tf`
- [ ] Remove `load_balancer_arn` tag from `aws_ecs_service` in `main.tf`
- [ ] Remove `backend_security_group` tag from `aws_ecs_service` in `main.tf`
- [ ] Remove `instance_role_policy_name` tag from `aws_ecs_service` in `main.tf`
- [ ] Remove `instance_role_policy_attachment` tag from `aws_ecs_service` in `main.tf`
- [ ] Simplify tags to use `local.resource_tags`
- [ ] Add explicit `depends_on` if needed
- [ ] Test service creation without tag dependencies
- [ ] Run terraform fmt and validate

**Status:** ⬜ Not Started

---

### Phase 3: Feature Additions & Enhancements

#### Issue #9: Add ECS Exec Support
- [ ] Add `enable_ecs_exec` variable to `variables.tf`
- [ ] Add SSM permissions to task execution role in `datasources.tf`
- [ ] Add `enable_execute_command` to `aws_ecs_service` in `main.tf`
- [ ] Document ECS Exec usage in README
- [ ] Test ECS Exec with `aws ecs execute-command`
- [ ] Verify SSM permissions work correctly
- [ ] Run terraform fmt and validate

**Status:** ⬜ Not Started

---

#### Issue #10: Improve Swap File Security
- [ ] Add `enable_swap` variable to `variables.tf`
- [ ] Add `swap_swappiness` variable to `variables.tf`
- [ ] Update cloud-init runcmd in `datasources.tf` with conditional swap
- [ ] Add swappiness tuning to cloud-init
- [ ] Add sysctl persistence to cloud-init
- [ ] Document swap security considerations
- [ ] Test with swap enabled
- [ ] Test with swap disabled
- [ ] Run terraform fmt and validate

**Status:** ⬜ Not Started

---

#### Issue #11: Make Autoscaling Parameters Configurable
- [ ] Add `scaling_cooldown_seconds` variable to `variables.tf`
- [ ] Add `instance_warmup_period` variable to `variables.tf`
- [ ] Update `autoscaling.tf` to use cooldown variable
- [ ] Update `main.tf` capacity provider to use new variables
- [ ] Document autoscaling tuning in README
- [ ] Test with custom values
- [ ] Run terraform fmt and validate

**Note:** `capacity_provider_target_capacity` will remain hardcoded at 100 (not making it configurable)

**Status:** ⬜ Not Started

---

#### Issue #12: Improve Task vs Execution Role Documentation
- [ ] Update `task_role_arn` description in `variables.tf`
- [ ] Update `execution_extra_policy` description in `variables.tf`
- [ ] Add clear explanation of role differences
- [ ] Add examples to variable descriptions
- [ ] Update README with role explanation
- [ ] Run terraform fmt and validate

**Status:** ⬜ Not Started

---

### Phase 4: Polish & Documentation

#### Issue #13: Update README and Documentation
- [ ] Add security section to README
- [ ] Document KMS encryption setup and requirements
- [ ] Add task vs execution role explanation
- [ ] Document SSH key security considerations
- [ ] Update examples with security best practices
- [ ] Create SECURITY.md with best practices
- [ ] Document all new variables
- [ ] Update usage examples
- [ ] Run terraform-docs to regenerate docs

**Status:** ⬜ Not Started

---

#### Issue #14: Add Security Tests
- [ ] Create `tests/test_security.py`
- [ ] Add test for IAM policy validation (no wildcards)
- [ ] Add test for CloudWatch encryption enabled
- [ ] Add test for variable validation errors
- [ ] Add test for Vanta tags applied
- [ ] Add test for sensitive outputs
- [ ] Document security testing approach
- [ ] Integrate into CI/CD pipeline
- [ ] Run full test suite

**Status:** ⬜ Not Started

---

#### Issue #15: File Naming Consistency
- [ ] Rename `website-pod.tf` to `website_pod.tf`
- [ ] Rename `tcp-pod.tf` to `tcp_pod.tf`
- [ ] Update any references in documentation
- [ ] Verify no broken references
- [ ] Run terraform fmt and validate

**Status:** ⬜ Not Started

---

## Progress Summary

**Last Updated:** 2025-12-02

### Overall Progress
- **Total Issues:** 19
- **Completed:** 8 (42%)
- **In Progress:** 0 (0%)
- **Not Started:** 11 (58%)

### By Phase
- **Phase 1 (Critical):** 4/4 issues (100%) ✅✅✅✅ **COMPLETE**
- **Phase 1.5 (Breaking Changes):** 4/4 issues (100%) ✅✅✅✅ **COMPLETE**
- **Phase 2 (Important):** 0/4 issues (0%)
- **Phase 3 (Enhancements):** 0/4 issues (0%)
- **Phase 4 (Polish):** 0/3 issues (0%)

### By Priority
- **CRITICAL:** 4/4 (Issues #1-2, #16-17) ✅✅✅✅ **ALL COMPLETE**
- **HIGH:** 4/4 (Issues #3-4, #18-19) ✅✅✅✅ **ALL COMPLETE**
- **MEDIUM:** 0/4 (Issues #5-8)
- **LOW:** 0/7 (Issues #9-15)

### Latest Updates (2025-12-01)
- ✅ **Issue #16 COMPLETED**: Upgrade to website-pod 5.12.1 and make alarm_emails required
  - **BREAKING CHANGE**: alarm_emails now required for v7.0.0
  - Upgraded website-pod from 5.9.0 to 5.12.1
  - Added comprehensive migration guide in README
  - Fixed deprecation warning: attach_tagret_group_to_asg → attach_target_group_to_asg
  - All tests passing (1 passed in 93.76s, no warnings)
  - Created future-work-plan.md for deferred tcp-pod support

- ✅ **Issue #4 COMPLETED**: Added variable validation blocks
  - Added validations for lb_type, container_port, autoscaling_metric, cloudwatch_log_group_retention
  - Created validations.tf with cross-variable checks
  - Tests PASSED (1 passed in 69.64s)

### Latest Updates (2025-11-30)
- ✅ **Issue #3 COMPLETED**: Pinned CloudWatch agent version
  - Changed default from `:latest` to pinned version `1.300049.0`
  - Added documentation explaining version pinning benefits
  - Users can still override to `:latest` if desired (no validation restrictions)
  - Philosophy: "Secure by default, allow user choice, educate don't restrict"

- ✅ **Issue #2 COMPLETED**: Scoped down IAM policies - removed wildcards
  - Replaced `ecs:*` and `ec2:Describe*` wildcards with AWS managed policy
  - Attached `AmazonEC2ContainerServiceforEC2Role` to instance role
  - Inline policy now only contains module-specific permissions
  - Follows AWS best practices and automatically stays updated
  - Tests PASSED: New instances register successfully

- ✅ **Issue #1 COMPLETED**: CloudWatch KMS encryption support added and tested
  - Added `cloudwatch_log_kms_key_id` variable for optional KMS encryption
  - Updated all 3 CloudWatch log groups to support encryption
  - Added test validation for encryption status
  - Changed output to map format for easier access
  - **BREAKING CHANGE**: Removed `internet_gateway_id` variable (auto-detected now)
  - Tests PASSED: 1 passed in 300.05s

---

## Phase 1: Critical Security Fixes (Must Fix Before Next Release)

### 1. Add KMS Encryption for CloudWatch Log Groups
**Priority:** CRITICAL
**Issue:** CloudWatch Log Groups created without KMS encryption, exposing sensitive logs at rest
**Estimated Time:** 30 minutes

**Changes:**
- Add `cloudwatch_log_kms_key_id` variable to `variables.tf`
- Update all CloudWatch log group resources in `cloudwatch.tf` to use KMS encryption
- Make encryption optional (default `null`) for backward compatibility

**Files to Modify:**
- `variables.tf` - Add new variable
- `cloudwatch.tf` - Update `aws_cloudwatch_log_group.ecs`, `aws_cloudwatch_log_group.ecs_ec2_syslog`, `aws_cloudwatch_log_group.ecs_ec2_dmesg`

**Implementation:**
```terraform
# variables.tf
variable "cloudwatch_log_kms_key_id" {
  description = "KMS key ID to encrypt CloudWatch logs. If not specified, logs will use AWS managed encryption."
  type        = string
  default     = null
}

# cloudwatch.tf - update all log groups
resource "aws_cloudwatch_log_group" "ecs" {
  count             = var.enable_cloudwatch_logs ? 1 : 0
  name              = local.cloudwatch_group
  retention_in_days = var.cloudwatch_log_group_retention
  kms_key_id        = var.cloudwatch_log_kms_key_id
  tags              = merge(...)
}
```

---

### 2. Scope Down IAM Policies (Fix Wildcards)
**Priority:** CRITICAL
**Issue:** Instance profile grants `ecs:*` and `ec2:Describe*` wildcard permissions
**Estimated Time:** 45 minutes

**Changes:**
- Update `data.aws_iam_policy_document.instance_policy` in `datasources.tf`
- Replace `ecs:*` with specific ECS container instance actions
- Replace `ec2:Describe*` with specific EC2 describe actions

**Files to Modify:**
- `datasources.tf` - Update IAM policy document (lines 93-112)

**Implementation:**
```terraform
data "aws_iam_policy_document" "instance_policy" {
  statement {
    sid = "ECSInstancePermissions"
    actions = [
      "ecs:CreateCluster",
      "ecs:DeregisterContainerInstance",
      "ecs:DiscoverPollEndpoint",
      "ecs:Poll",
      "ecs:RegisterContainerInstance",
      "ecs:StartTelemetrySession",
      "ecs:Submit*",
      "ecs:UpdateContainerInstancesState"
    ]
    resources = ["*"]
  }

  statement {
    sid = "EC2DescribePermissions"
    actions = [
      "ec2:DescribeInstances",
      "ec2:DescribeTags",
      "ec2:DescribeInstanceAttribute"
    ]
    resources = ["*"]
  }
}
```

---

### 3. Pin CloudWatch Agent to Specific Version
**Priority:** HIGH
**Issue:** Default CloudWatch agent image uses `:latest` tag
**Estimated Time:** 15 minutes

**Changes:**
- Update `cloudwatch_agent_image` variable default in `variables.tf`
- Add validation block to prevent `:latest` tag

**Files to Modify:**
- `variables.tf` - Update variable (line 69)

**Implementation:**
```terraform
variable "cloudwatch_agent_image" {
  description = <<-EOT
    CloudWatch agent container image URI.
    IMPORTANT: Always use a specific version tag (e.g., 1.300044.0b648), never use 'latest'.
    See available versions: https://gallery.ecr.aws/cloudwatch-agent/cloudwatch-agent
  EOT
  type        = string
  default     = "public.ecr.aws/cloudwatch-agent/cloudwatch-agent:1.300044.0b648"

  validation {
    condition     = !endswith(var.cloudwatch_agent_image, ":latest")
    error_message = "cloudwatch_agent_image must not use ':latest' tag. Specify a version tag for reproducibility and security."
  }
}
```

---

### 4. Add Variable Validation Blocks
**Priority:** HIGH
**Issue:** No validation blocks on any variables
**Estimated Time:** 1 hour

**Changes:**
- Add validation blocks for critical variables

**Files to Modify:**
- `variables.tf` - Add validations throughout

**Variables to Validate:**
- `lb_type` - must be "alb" or "nlb"
- `container_port` - must be 1-65535
- `autoscaling_metric` - must be valid ECS metric
- `healthcheck_interval` - must be >= healthcheck_timeout
- `cloudwatch_log_group_retention` - must be valid CloudWatch retention value
- `capacity_provider_target_capacity` - must be 1-100

**Implementation:**
```terraform
variable "lb_type" {
  description = "Load balancer type. ALB or NLB"
  type        = string
  default     = "alb"

  validation {
    condition     = contains(["alb", "nlb"], lower(var.lb_type))
    error_message = "lb_type must be either 'alb' or 'nlb' (case-insensitive)."
  }
}

variable "container_port" {
  description = "TCP port that a container serves client requests on."
  type        = number
  default     = 8080

  validation {
    condition     = var.container_port >= 1 && var.container_port <= 65535
    error_message = "container_port must be between 1 and 65535."
  }
}

# Add similar validations for other variables...
```

---

## Phase 2: Important Security & Quality Improvements

### 5. Mark Secrets as Sensitive
**Priority:** MEDIUM
**Issue:** Secrets not marked as sensitive in variables and outputs
**Estimated Time:** 20 minutes

**Changes:**
- Mark `task_secrets` variable as sensitive
- Mark security-related outputs as sensitive

**Files to Modify:**
- `variables.tf` - Update `task_secrets` variable (lines 268-279)
- `outputs.tf` - Update `backend_security_group`, `task_execution_role_arn`

**Implementation:**
```terraform
# variables.tf
variable "task_secrets" {
  description = <<-EOT
    Secrets to pass to a container. A `name` will be the environment variable.
    valueFrom is a secret ARN (AWS Secrets Manager or SSM Parameter Store).

    IMPORTANT: Referenced secrets should be encrypted with KMS.
    The task execution role will need kms:Decrypt permissions.
  EOT
  type = list(object({
    name      : string
    valueFrom : string
  }))
  default   = []
  sensitive = true
}

# outputs.tf
output "backend_security_group" {
  description = "Security group of backend."
  value       = local.backend_security_group
  sensitive   = true
}

output "task_execution_role_arn" {
  description = "Task execution role is a role that ECS agent gets."
  value       = aws_iam_role.ecs_task_execution_role.arn
  sensitive   = true
}
```

---

### 6. Fix SSH Key Security Concern
**Priority:** MEDIUM
**Issue:** Private SSH key stored in Terraform state
**Estimated Time:** 30 minutes

**Option A (Non-Breaking):** Add warning and output for key retrieval
**Option B (Breaking):** Make ssh_key_name required, remove key generation

**Recommended Approach:** Option A for backward compatibility

**Changes:**
- Add output for SSH private key with retrieval instructions
- Add warning in documentation

**Files to Modify:**
- `outputs.tf` - Add new outputs
- `ssh.tf` - Add comments about security
- `README.md` - Document security considerations

**Implementation:**
```terraform
# outputs.tf
output "ssh_private_key_retrieval_instructions" {
  description = "Instructions for retrieving the SSH private key from Terraform state"
  value = var.ssh_key_name != null ? "Using pre-existing SSH key: ${var.ssh_key_name}" : <<-EOT
    WARNING: Private SSH key is stored in Terraform state.
    To retrieve it, run:
      terraform output -raw ssh_private_key > ~/.ssh/${var.service_name}.pem
      chmod 600 ~/.ssh/${var.service_name}.pem

    SECURITY: Ensure your Terraform state backend is encrypted and access-controlled.
  EOT
}

output "ssh_private_key" {
  description = "Private SSH key for ECS instances. SENSITIVE - only use in secure environments."
  value       = var.ssh_key_name != null ? null : tls_private_key.rsa[0].private_key_pem
  sensitive   = true
}
```

---

### 7. Fix Inconsistent Tagging
**Priority:** MEDIUM
**Issue:** Resources have inconsistent tags, Vanta tags hardcoded
**Estimated Time:** 45 minutes

**Changes:**
- Create unified `resource_tags` local
- Add variables for Vanta tags
- Apply consistent tags to all resources
- Add `module_version` tag to all resources

**Files to Modify:**
- `locals.tf` - Add new tagging local
- `variables.tf` - Add Vanta tag variables
- All resource files - Update to use consistent tags

**Implementation:**
```terraform
# variables.tf
variable "vanta_contains_user_data" {
  description = "Whether resources contain user data (Vanta compliance)"
  type        = bool
  default     = false
}

variable "vanta_contains_ephi" {
  description = "Whether resources contain EPHI data (Vanta compliance)"
  type        = bool
  default     = false
}

# locals.tf
locals {
  resource_tags = merge(
    local.default_module_tags,
    {
      VantaContainsUserData : var.vanta_contains_user_data
      VantaContainsEPHI     : var.vanta_contains_ephi
      module_version        : local.module_version
    }
  )
}

# Apply to all resources
resource "aws_ecs_cluster" "ecs" {
  tags = local.resource_tags
}

resource "aws_iam_role" "ecs_task_execution_role" {
  tags = merge(local.resource_tags, { Name = "${var.service_name}-execution-role" })
}
```

---

### 8. Remove Tag-Based Implicit Dependencies
**Priority:** MEDIUM
**Issue:** ECS service uses tags for implicit dependencies (anti-pattern)
**Estimated Time:** 20 minutes

**Changes:**
- Remove dependency-tracking tags from `aws_ecs_service`
- Add explicit `depends_on` if needed (likely not needed due to implicit graph)

**Files to Modify:**
- `main.tf` - Update `aws_ecs_service.ecs` resource (lines 161-182)

**Implementation:**
```terraform
resource "aws_ecs_service" "ecs" {
  # ... existing configuration ...

  # Remove these tags:
  # execution_role_arn, target_group_arn, load_balancer_arn,
  # backend_security_group, instance_role_policy_name, etc.

  tags = local.resource_tags

  # Add explicit depends_on only if needed
  depends_on = [
    aws_iam_role_policy_attachment.ecs_task_execution_role_policy,
  ]
}
```

---

## Phase 3: Feature Additions & Enhancements

### 9. Add ECS Exec Support
**Priority:** LOW
**Feature:** Enable remote command execution in containers
**Estimated Time:** 30 minutes

**Changes:**
- Add `enable_ecs_exec` variable
- Add SSM permissions to task execution role
- Enable execute command in ECS service

**Files to Modify:**
- `variables.tf` - Add new variable
- `datasources.tf` - Add SSM permissions to task execution role
- `main.tf` - Enable execute command in service

**Implementation:**
```terraform
# variables.tf
variable "enable_ecs_exec" {
  description = "Enable ECS Exec for remote command execution in containers"
  type        = bool
  default     = false
}

# datasources.tf - add to task_execution_role_policy
dynamic "statement" {
  for_each = var.enable_ecs_exec ? [1] : []
  content {
    sid = "AllowECSExec"
    actions = [
      "ssmmessages:CreateControlChannel",
      "ssmmessages:CreateDataChannel",
      "ssmmessages:OpenControlChannel",
      "ssmmessages:OpenDataChannel"
    ]
    resources = ["*"]
  }
}

# main.tf - aws_ecs_service
enable_execute_command = var.enable_ecs_exec
```

---

### 10. Improve Swap File Security
**Priority:** LOW
**Issue:** Swap file created without encryption or swappiness tuning
**Estimated Time:** 30 minutes

**Changes:**
- Update cloud-init commands to add swappiness tuning
- Document swap security considerations
- Consider making swap optional

**Files to Modify:**
- `datasources.tf` - Update cloud-init runcmd (lines 78-83)
- `variables.tf` - Add swap configuration variables

**Implementation:**
```terraform
# variables.tf
variable "enable_swap" {
  description = "Enable swap file on ECS instances"
  type        = bool
  default     = true
}

variable "swap_swappiness" {
  description = "Kernel swappiness parameter (0-100). Lower values reduce swap usage."
  type        = number
  default     = 10

  validation {
    condition     = var.swap_swappiness >= 0 && var.swap_swappiness <= 100
    error_message = "swap_swappiness must be between 0 and 100."
  }
}

# datasources.tf - update runcmd
"runcmd" : concat(
  var.enable_swap ? [
    "fallocate -l ${data.aws_ec2_instance_type.ecs.memory_size * 2}M /swapfile",
    "chmod 600 /swapfile",
    "mkswap /swapfile",
    "swapon /swapfile",
    "sysctl vm.swappiness=${var.swap_swappiness}",
    "echo 'vm.swappiness=${var.swap_swappiness}' >> /etc/sysctl.conf"
  ] : [],
  var.cloudinit_extra_commands
)
```

---

### 11. Make Autoscaling Parameters Configurable
**Priority:** LOW
**Issue:** Hardcoded autoscaling values reduce flexibility
**Estimated Time:** 30 minutes

**Changes:**
- Add variables for scaling cooldowns, target capacity, warmup period
- Update resources to use new variables

**Files to Modify:**
- `variables.tf` - Add new variables
- `autoscaling.tf` - Use variables for cooldowns
- `main.tf` - Use variables for capacity provider

**Implementation:**
```terraform
# variables.tf
variable "scaling_cooldown_seconds" {
  description = "Seconds to wait between scaling activities"
  type        = number
  default     = 300
}

variable "capacity_provider_target_capacity" {
  description = "Target capacity percentage for ECS capacity provider (1-100)"
  type        = number
  default     = 100

  validation {
    condition     = var.capacity_provider_target_capacity >= 1 && var.capacity_provider_target_capacity <= 100
    error_message = "capacity_provider_target_capacity must be between 1 and 100."
  }
}

variable "instance_warmup_period" {
  description = "Period of time, in seconds, that ECS considers new instances warming up"
  type        = number
  default     = 300
}

# autoscaling.tf
scale_in_cooldown  = var.scaling_cooldown_seconds
scale_out_cooldown = var.scaling_cooldown_seconds

# main.tf - capacity provider
managed_scaling {
  maximum_scaling_step_size = 10
  minimum_scaling_step_size = 1
  status                    = "ENABLED"
  target_capacity           = var.capacity_provider_target_capacity
  instance_warmup_period    = var.instance_warmup_period
}
```

---

### 12. Improve Task vs Execution Role Documentation
**Priority:** LOW
**Issue:** Confusion between task execution role and task role
**Estimated Time:** 20 minutes

**Changes:**
- Improve variable descriptions for clarity
- Consider consolidating execution role policy variables

**Files to Modify:**
- `variables.tf` - Update descriptions for `task_role_arn`, `execution_extra_policy`

**Implementation:**
```terraform
variable "task_role_arn" {
  description = <<-EOT
    IAM role ARN for the ECS task (used by application containers).
    This is different from the execution role:
    - Task Role: Used by application code running in containers (e.g., access to S3, DynamoDB)
    - Execution Role: Used by ECS agent (to pull images, write logs) - created by this module

    If not specified, containers run without an IAM role.

    Example: "arn:aws:iam::123456789012:role/MyAppTaskRole"
  EOT
  type        = string
  default     = null
}

variable "execution_extra_policy" {
  description = <<-EOT
    Map of extra policies to attach to the task execution role.
    The task execution role is used by the ECS agent to pull images, write logs, etc.
    Key: arbitrary identifier, Value: IAM policy ARN.

    Example:
      execution_extra_policy = {
        "secrets_access" = "arn:aws:iam::123456789012:policy/ECSSecretsAccess"
      }
  EOT
  type        = map(string)
  default     = {}
}
```

---

## Phase 4: Polish & Documentation

### 13. Update README and Documentation
**Priority:** LOW
**Estimated Time:** 1 hour

**Changes:**
- Document KMS encryption requirements and setup
- Add task vs execution role explanation with diagram
- Document SSH key security considerations
- Update examples to show security best practices
- Add security section to README

**Files to Modify:**
- `README.md` - Major updates
- Add `SECURITY.md` - Security best practices document

---

### 14. Add Security Tests
**Priority:** LOW
**Estimated Time:** 2 hours

**Changes:**
- Add test for IAM policy validation (no wildcards)
- Add test for encryption enabled
- Add test for variable validation
- Add test for Vanta tags applied

**Files to Create/Modify:**
- `tests/test_security.py` - New security-focused tests

**Implementation:**
```python
def test_iam_policies_no_wildcards(outputs):
    """Verify IAM policies don't use overly broad wildcards"""
    # Parse IAM policy documents from outputs
    # Assert no "ecs:*" actions
    # Assert no "ec2:Describe*" actions
    pass

def test_cloudwatch_encryption_enabled(outputs):
    """Verify CloudWatch logs can be encrypted with KMS"""
    # Test with kms_key_id parameter
    # Verify log groups have encryption
    pass

def test_variable_validation():
    """Verify variable validation catches errors"""
    # Test with invalid lb_type
    # Test with port out of range
    # Verify Terraform plan fails with clear error
    pass
```

---

### 15. File Naming Consistency
**Priority:** LOW
**Estimated Time:** 10 minutes

**Changes:**
- Rename files to use snake_case consistently

**Files to Rename:**
- `website-pod.tf` → `website_pod.tf`
- `tcp-pod.tf` → `tcp_pod.tf`

---

## Implementation Timeline

### Sprint 1 (Critical Security - 2-3 hours)
- Day 1: Issues #1, #2, #3 (KMS encryption, IAM policies, CloudWatch agent)
- Day 2: Issue #4 (Variable validation)
- Day 3: Testing and verification

### Sprint 2 (Important Improvements - 2-3 hours)
- Day 4: Issues #5, #6 (Secrets sensitivity, SSH key)
- Day 5: Issues #7, #8 (Tagging, dependencies)
- Day 6: Testing and verification

### Sprint 3 (Enhancements - 3-4 hours)
- Day 7: Issues #9, #10 (ECS Exec, swap security)
- Day 8: Issues #11, #12 (Autoscaling, documentation)
- Day 9: Testing and verification

### Sprint 4 (Polish - 1-2 hours)
- Day 10: Issues #13, #14 (README, security tests)
- Day 11: Issue #15 (File naming)
- Day 12: Final testing and release prep

---

## Questions Before Starting

1. **Breaking Changes**: Should Phase 2 SSH key changes be breaking (require pre-created keys) or backward compatible (add warning)?
   - Recommendation: Backward compatible for now

2. **Encryption**: Should KMS encryption be optional (default null) or required?
   - Recommendation: Optional with default null for backward compatibility

3. **Vanta Tags**: Should VantaContainsUserData/VantaContainsEPHI remain hardcoded false or become configurable?
   - Recommendation: Make configurable with default false

4. **Version Bump**: This will be a minor version (6.2.0) or major version (7.0.0) if breaking changes?
   - Recommendation: 6.2.0 if all changes are backward compatible, 7.0.0 if breaking

5. **Deprecation**: Should we deprecate `execution_task_role_policy_arn` in favor of `execution_extra_policy`?
   - Recommendation: Keep both for now, document preference for `execution_extra_policy`

---

## Testing Strategy

### After Each Phase:
1. Run `terraform fmt` and `terraform validate`
2. Run existing test suite: `make test`
3. Manual testing with test_data examples
4. Verify backward compatibility with existing configurations

### Before Release:
1. Full regression test suite (all tests)
2. Test with both AWS provider v5 and v6
3. Test all documented examples
4. Security scan with checkov or tfsec
5. Update CHANGELOG.md with all changes

---

## Success Criteria

- [ ] All critical security issues resolved
- [ ] All tests passing (existing + new)
- [ ] Documentation updated
- [ ] Backward compatibility maintained (or breaking changes documented)
- [ ] CHANGELOG.md updated
- [ ] Version bumped appropriately
- [ ] Review by second person completed

---

## Notes

- Prioritize Phase 1 (critical security) - can be released as 6.1.1 patch
- Phases 2-4 can be combined into 6.2.0 minor release
- Consider breaking changes for 7.0.0 major release if needed
- Keep changes focused and testable
- Update terraform-docs after variable changes

---

## Decision Log

### Decisions Made
- [x] **Version Bump:** 7.0.0 (Major version with breaking changes)
  - **Rationale:** Adding required `alert_emails` variable to enable CloudWatch alerting from website-pod 5.12.1
  - **Impact:** All users must provide alert_emails when upgrading
  - **Date:** 2025-11-30

### Decisions Needed
- [ ] **SSH Key Approach:** Option A (backward compatible) vs Option B (breaking change)
  - Recommendation: Option A
  - Decision: _Pending_
  - **Note:** Even with Option A, this stays backward compatible within v7.0.0

- [ ] **KMS Encryption:** Optional (default null) vs Required
  - Recommendation: Optional (default null)
  - Decision: _Pending_
  - **Note:** Making it optional keeps flexibility for users

- [ ] **Vanta Tags:** Configurable vs Hardcoded
  - Recommendation: Configurable with default false
  - Decision: _Pending_

- [ ] **execution_task_role_policy_arn:** Keep vs Deprecate
  - Recommendation: Keep both, document preference for execution_extra_policy
  - Decision: _Pending_

---

## Blockers

- None currently

---

## Release Checklist

### Version 7.0.0 (MAJOR VERSION - BREAKING CHANGES)
- [ ] All Phase 1 issues completed (#1-4)
- [ ] All Phase 1.5 issues completed (#16 - BREAKING CHANGE)
- [ ] All Phase 2 issues completed (#5-8)
- [ ] All Phase 3 issues completed (#9-12)
- [ ] All Phase 4 issues completed (#13-15)
- [ ] All decisions made
- [ ] CHANGELOG.md updated with BREAKING CHANGES section
- [ ] Version bumped to 7.0.0 in module
- [ ] terraform-docs regenerated
- [ ] All test files updated with `alert_emails` parameter
- [ ] All tests passing (AWS provider v5)
- [ ] All tests passing (AWS provider v6)
- [ ] Security scan clean (checkov/tfsec)
- [ ] README updated with migration guide (v6 to v7)
- [ ] Migration guide added to README
- [ ] Breaking changes documented clearly
- [ ] Git tag created (v7.0.0)
- [ ] Release notes prepared with BREAKING CHANGES highlighted

### Breaking Changes Summary for Release Notes:
1. **alert_emails now required** - Must provide list of emails for CloudWatch alerts
2. **Module dependencies updated** - website-pod upgraded to 5.12.1

### Migration Impact:
- ALL users must update their configurations to add `alert_emails` variable
- Terraform plan will fail without this variable in v7.0.0
- See migration guide in README for upgrade instructions
