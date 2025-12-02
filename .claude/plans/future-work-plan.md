# Future Work Plan

**Module:** terraform-aws-ecs
**Document Purpose:** Track deferred tasks that depend on external dependencies or are planned for future releases
**Last Updated:** 2025-12-01

---

## Deferred Tasks

### Waiting on External Dependencies

#### Add alarm_emails support for tcp-pod module
**Blocked By:** tcp-pod module doesn't support `alarm_emails` parameter yet (current version: 0.6.0)
**Priority:** MEDIUM
**Estimated Time:** 10 minutes (once tcp-pod supports it)

**Task:**
- Pass `alarm_emails` to tcp-pod module in `tcp-pod.tf`
- Similar to how it's already implemented for website-pod module

**Implementation:**
```terraform
# tcp-pod.tf
module "tcp-pod" {
  count   = var.lb_type == "nlb" ? 1 : 0
  source  = "registry.infrahouse.com/infrahouse/tcp-pod/aws"
  version = "~> 0.7"  # Or whatever version adds alarm_emails support

  # ... existing parameters ...
  alarm_emails = var.alarm_emails  # Add this parameter
}
```

**Next Steps:**
1. Monitor tcp-pod module releases for alarm_emails support
2. Update tcp-pod version constraint when support is added
3. Add alarm_emails parameter to module call
4. Test with NLB configuration
5. Update relevant test files

**Related:**
- Issue #16 in terraform-fixes-plan.md (Phase 1.5)
- alarm_emails already implemented for website-pod module

---

## Future Enhancements (Post v7.0.0 Release)

**Status:** Planned for v7.1.0 or later releases
**Source:** Moved from terraform-fixes-plan.md after v7.0.0 completion

### Phase 2: Important Security & Quality Improvements

#### Issue #5: Mark Secrets as Sensitive
**Priority:** MEDIUM
**Estimated Time:** 20 minutes

**Changes:**
- Mark `task_secrets` variable as `sensitive = true`
- Mark security-related outputs as sensitive

**Benefits:**
- Prevents secrets from appearing in Terraform plan output
- Better security hygiene

---

#### Issue #6: Fix SSH Key Security Concern
**Priority:** MEDIUM
**Estimated Time:** 30 minutes
**Approach:** Option A (backward compatible - add warnings)

**Changes:**
- Add `ssh_private_key_retrieval_instructions` output
- Add `ssh_private_key` sensitive output
- Document SSH key security in README

**Benefits:**
- Users aware of private key in state
- Clear instructions for secure key retrieval

---

#### Issue #7: Fix Inconsistent Tagging
**Priority:** MEDIUM
**Estimated Time:** 45 minutes

**Changes:**
- Create unified `resource_tags` local
- Add `vanta_contains_user_data` and `vanta_contains_ephi` variables
- Apply consistent tags to all resources
- Add `module_version` tag everywhere

**Benefits:**
- Consistent tagging across all resources
- Configurable Vanta compliance tags
- Better resource tracking

---

#### Issue #8: Remove Tag-Based Implicit Dependencies
**Priority:** MEDIUM
**Estimated Time:** 20 minutes

**Changes:**
- Remove dependency-tracking tags from `aws_ecs_service`
- Use explicit `depends_on` if needed
- Simplify to use `local.resource_tags`

**Benefits:**
- Cleaner code following Terraform best practices
- Explicit dependency management

---

### Phase 3: Feature Additions & Enhancements

#### Issue #9: Add ECS Exec Support
**Priority:** LOW
**Estimated Time:** 30 minutes

**Changes:**
- Add `enable_ecs_exec` variable
- Add SSM permissions to task execution role
- Enable execute command in ECS service

**Benefits:**
- Remote command execution in containers for debugging
- Better operational support

---

#### Issue #10: Improve Swap File Security
**Priority:** LOW
**Estimated Time:** 30 minutes

**Changes:**
- Add `enable_swap` and `swap_swappiness` variables
- Make swap file optional
- Add swappiness tuning

**Benefits:**
- Configurable swap behavior
- Better performance tuning options

---

#### Issue #11: Make Autoscaling Parameters Configurable
**Priority:** LOW
**Estimated Time:** 30 minutes

**Changes:**
- Add `scaling_cooldown_seconds` variable
- Add `instance_warmup_period` variable
- Update autoscaling resources to use new variables

**Note:** `capacity_provider_target_capacity` will remain hardcoded at 100

**Benefits:**
- Fine-tuned autoscaling behavior
- Better control over scaling performance

---

#### Issue #12: Improve Task vs Execution Role Documentation
**Priority:** LOW
**Estimated Time:** 20 minutes

**Changes:**
- Improve variable descriptions for `task_role_arn` and `execution_extra_policy`
- Add clear explanation of role differences
- Add examples to variable descriptions

**Benefits:**
- Reduced user confusion
- Better understanding of IAM roles

---

### Phase 4: Polish & Documentation

#### Issue #13: Update README and Documentation
**Priority:** LOW
**Estimated Time:** 1 hour

**Changes:**
- Add security section to README
- Document KMS encryption setup
- Add task vs execution role explanation
- Document SSH key security
- Create SECURITY.md with best practices

**Benefits:**
- Comprehensive documentation
- Better user guidance on security

---

#### Issue #14: Add Security Tests
**Priority:** LOW
**Estimated Time:** 2 hours

**Changes:**
- Create `tests/test_security.py`
- Add test for IAM policy validation (no wildcards)
- Add test for CloudWatch encryption enabled
- Add test for variable validation errors
- Add test for Vanta tags applied

**Benefits:**
- Automated security validation
- Prevent regressions

---

#### Issue #15: File Naming Consistency
**Priority:** LOW
**Estimated Time:** 10 minutes

**Changes:**
- Rename `website-pod.tf` → `website_pod.tf`
- Rename `tcp-pod.tf` → `tcp_pod.tf`

**Benefits:**
- Consistent snake_case naming
- Better code style adherence

---

## Planning Notes

### v7.0.0 Release (COMPLETED)
**Released:** 2025-12-01
**Completed Issues:** #1, #2, #3, #4, #16
- All critical security fixes
- Breaking change: alarm_emails required
- Ready for production use

### v7.1.0 (Proposed)
**Target:** Phase 2 issues (#5-8)
**Estimated Time:** ~2 hours
**Focus:** Security & quality improvements (all backward compatible)

### v7.2.0 or v8.0.0 (Future)
**Target:** Phase 3-4 issues (#9-15)
**Estimated Time:** ~4-5 hours
**Focus:** New features and polish

---

## Notes

- v7.0.0 includes all critical and high priority issues
- All remaining work is medium or low priority
- No blockers for any future issues
- Issues can be implemented incrementally in minor releases
- Keep backward compatibility for v7.x.x releases