# Future Work Plan

**Module:** terraform-aws-ecs
**Document Purpose:** Track deferred tasks that depend on external dependencies or are planned for future releases

---

## Deferred Tasks

### Waiting on External Dependencies

#### Add alert_emails support for tcp-pod module
**Blocked By:** tcp-pod module doesn't support `alert_emails` parameter yet (current version: 0.6.0)

**Task:**
- Pass `alert_emails` to tcp-pod module in `tcp-pod.tf`
- Similar to how it's already implemented for website-pod module

**Implementation:**
```terraform
# tcp-pod.tf
module "tcp-pod" {
  count   = var.lb_type == "nlb" ? 1 : 0
  source  = "registry.infrahouse.com/infrahouse/tcp-pod/aws"
  version = "~> 0.7"  # Or whatever version adds alert_emails support

  # ... existing parameters ...
  alert_emails = var.alert_emails  # Add this parameter
}
```

**Next Steps:**
1. Monitor tcp-pod module releases for alert_emails support
2. Update tcp-pod version constraint when support is added
3. Add alert_emails parameter to module call
4. Test with NLB configuration
5. Update relevant test files

**Related:**
- Issue #16 in terraform-fixes-plan.md (Phase 1.5)
- alert_emails already implemented for website-pod module

---

## Future Enhancements

_This section is for features we'd like to add but aren't currently prioritized_

### Ideas for Consideration
- None yet

---

## Notes

- This document tracks work that can't be completed now due to external dependencies
- When dependencies are resolved, move tasks back to the main terraform-fixes-plan.md
- Keep this document updated as new blockers are identified