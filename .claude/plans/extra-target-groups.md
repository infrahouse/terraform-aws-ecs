# Extra Target Groups Plan

**Module:** terraform-aws-ecs
**Branch:** extra-target-groups
**Related:** PR #134 (community request for multi-port container support)
**Last Updated:** 2026-02-24

---

## Context

A user (Pasha Dudka) submitted PR #134 to support containers that listen
on multiple TCP ports (e.g., Grafana Tempo: port 3200 for query API +
port 4317 for OTLP gRPC ingest).

**Design decision:** The ECS module creates everything internally --
target groups, ALB listeners, port mappings, and ECS service load
balancer registrations. This avoids the chicken-and-egg problem where
AWS requires a target group to be associated with a listener before
an ECS service can register with it.

**Key constraint discovered during implementation:** AWS ECS
`CreateService` fails with `InvalidParameterException` if a target
group is not associated with a load balancer (i.e., not referenced
by any listener or listener rule). Since the ALB is created inside
the website-pod sub-module, an externally-created target group
cannot be associated with a listener before the ECS service tries
to use it -- creating a circular dependency. The solution is to
have the module create both the target group and the listener.

---

## Scope of Changes

### What changes (terraform-aws-ecs module only)

| File | Change |
|------|--------|
| `variables.tf` | New `extra_target_groups` variable |
| `main.tf` | Extend `portMappings` + dynamic `load_balancer` block |
| `extra_target_groups.tf` | New TG + listener resources |
| `outputs.tf` | New `target_group_arn` output |
| `test_data/httpd_extra_tg/` | New test fixture |
| `tests/test_extra_tg.py` | Integration test |

### What does NOT change

- `modules/website-pod/` -- no changes needed
- `modules/tcp-pod/` -- no changes needed
- `autoscaling.tf` -- autoscaling stays on the primary target group
- `locals.tf` -- no changes to existing locals

---

## Implementation

### Variable: `extra_target_groups`

```hcl
variable "extra_target_groups" {
  type = map(object({
    listener_port  = number
    container_port = number
    protocol       = optional(string, "HTTP")
    health_check = optional(object({
      path     = optional(string, "/")
      port     = optional(string, "traffic-port")
      matcher  = optional(string, "200-299")
      interval = optional(number, 30)
      timeout  = optional(number, 5)
    }), {})
  }))
  default = {}
}
```

**Key design decisions:**
- **`map(object)`** -- `for_each` with a map avoids index-shifting.
  Reordering map keys does not force ECS service replacement.
- **Module creates TG + listener** -- avoids the circular dependency.
- **Each entry gets its own ALB listener on `listener_port`** -- this
  is the natural pattern for multi-port services.

### Resources: `extra_target_groups.tf`

For each entry, the module creates:
- `aws_lb_target_group.extra[key]` -- target group for the container
  port
- `aws_lb_listener.extra[key]` -- ALB listener on `listener_port`
  forwarding to the target group

### ECS service: `main.tf`

- `portMappings` extended with `concat()` to include extra ports
- Dynamic `load_balancer` block references
  `aws_lb_target_group.extra[key].arn`

---

## Usage Example

```hcl
module "tempo" {
  source  = "registry.infrahouse.com/infrahouse/ecs/aws"
  version = "X.Y.Z"

  service_name   = "tempo"
  docker_image   = "grafana/tempo:latest"
  container_port = 3200  # Primary: query API

  extra_target_groups = {
    otlp_grpc = {
      listener_port  = 4317
      container_port = 4317
      protocol       = "HTTP"
      health_check = {
        path    = "/health"
        matcher = "200"
      }
    }
  }

  # ... other required variables ...
}
```

---

## Version Impact

Minor version bump (backward-compatible feature addition):
- Default value `{}` means existing callers are unaffected
- No changes to existing variables, outputs, or behavior

---

## Checklist

- [x] Add `extra_target_groups` variable to `variables.tf`
- [x] Create `extra_target_groups.tf` with TG + listener resources
- [x] Modify `portMappings` in task definition (`main.tf`)
- [x] Add dynamic `load_balancer` block to ECS service (`main.tf`)
- [x] Add `target_group_arn` output to `outputs.tf`
- [x] Create test fixture in `test_data/httpd_extra_tg/`
- [x] Create integration test in `tests/test_extra_tg.py`
- [x] Run `terraform fmt -recursive`
- [ ] Run test: `TEST_PATH=tests/test_extra_tg.py TEST_FILTER="test_extra_target_groups and aws-6" make test-keep`
- [ ] Respond to PR #134 author with feedback