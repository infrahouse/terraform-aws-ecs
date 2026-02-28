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

## gRPC / protocol_version Support

**Last Updated:** 2026-02-26
**Triggered by:** User deploying Grafana Tempo with OTLP gRPC extra target group

### Problem

User got this error when deploying an extra target group with a specific health check port:

```
InvalidParameterException: The task definition is configured to use a dynamic host port,
but the target group with targetGroupArn ... has a health check port specified.
```

**Root cause:** With `target_type = "instance"` and ECS bridge networking, the host port
is dynamically assigned (host_port = 0). AWS does not allow a specific health check port
in this case — it must be `"traffic-port"` (the default in our variable).

The user overrode `health_check.port` with a numeric value, which is incompatible.

### Missing feature: `protocol_version`

The `aws_lb_target_group` resource supports `protocol_version` with values:
- `HTTP1` (default)
- `HTTP2`
- `gRPC`

Ref: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_target_group.html

For gRPC target groups, `protocol_version = "GRPC"` changes health check behavior:
- Health check uses gRPC health checking protocol (`grpc.health.v1.Health/Check`)
- `matcher` becomes a gRPC status code (e.g., `"0"` for OK, `"12"` for UNIMPLEMENTED)
- `path` becomes the gRPC service name (e.g., `"/"` for default)
- `port` must be `"traffic-port"` (dynamic host port constraint)

### Changes needed

| File | Change |
|------|--------|
| `variables.tf` | Add `protocol_version = optional(string, null)` to `extra_target_groups` object |
| `extra_target_groups.tf` | Add `protocol_version = each.value.protocol_version` to TG resource |
| `test_data/httpd_extra_tg/main.tf` | Optionally add a gRPC TG entry for testing |

### Updated variable shape

```hcl
variable "extra_target_groups" {
  type = map(object({
    listener_port    = number
    container_port   = number
    protocol         = optional(string, "HTTP")
    protocol_version = optional(string, null)   # NEW: "HTTP1", "HTTP2", "gRPC"
    deregistration_delay = optional(number, 300)
    health_check = optional(object({
      path     = optional(string, "/")
      port     = optional(string, "traffic-port")
      matcher  = optional(string, "200-299")
      interval = optional(number, 30)
      timeout  = optional(number, 5)
    }), {})
  }))
}
```

### Usage example (Tempo with gRPC OTLP)

```hcl
extra_target_groups = {
  otlp_grpc = {
    listener_port    = 4317
    container_port   = 4317
    protocol         = "HTTP"
    protocol_version = "GRPC"
    health_check = {
      path    = "/"              # gRPC service name; "/" = default
      matcher = "0-99"           # gRPC status codes; 0 = OK
    }
    # port defaults to "traffic-port" — required for dynamic host ports
  }
}
```

### Testing with Tempo container

A dedicated test fixture using `grafana/tempo` could validate gRPC target groups
end-to-end. Tempo exposes:
- Port 3200: HTTP API + `/ready` health check (primary service)
- Port 4317: OTLP gRPC ingest (extra target group)

Test fixture would use `container_port = 3200` for the primary service and
`extra_target_groups` with `container_port = 4317, protocol_version = "GRPC"`.

Tempo needs minimal config to start (a YAML config file). The container could
be configured via `container_command` or a custom Docker image.

For the gRPC health check matcher: Tempo may not implement the gRPC health
service, so `matcher = "12"` (UNIMPLEMENTED) would still prove the port is
alive and the target group is correctly configured.

Alternatively, keep the existing httpd test and just add `protocol_version`
to verify Terraform accepts the configuration without errors.

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