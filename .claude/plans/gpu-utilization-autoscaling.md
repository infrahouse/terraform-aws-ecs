# GPU Utilization Autoscaling Plan

**Module:** terraform-aws-ecs
**Branch:** gpu-utilization-autoscaling (proposed)
**Related:** PR #171 (Prometheus scraping — superseded approach), Slack "Discuss Autoscaling For GPU Instance"
**Blog:** https://infrahouse.com/blog/2026-06-14-serving-a-7b-model-on-ecs-gpu/
**Last Updated:** 2026-07-17

---

## Context

We serve a GPU model (Qwen-short via vLLM on `g5.2xlarge`, `gpu_count = 1`) on ECS
and need two things:

1. Scale the ECS service on GPU utilization.
2. Keep a minimum number of GPU instances always available for production,
   backed by On-Demand Capacity Reservations (ODCR).

### Decision on the metric source

PR #171 added Prometheus scraping so a consumer could scale on the app's own
metrics (`vllm:gpu_cache_usage_perc`, `vllm:num_requests_waiting`). That works but
ties autoscaling to vLLM's metric surface.

We are taking the other approach: collect **native NVIDIA GPU utilization** through
the CloudWatch agent's `nvidia_gpu` collector and scale on that. It does not depend
on vLLM, so the same mechanism works for any GPU workload the module runs.

Naming detail that matters for the scaling policy: `utilization_gpu` is the
*measurement key* you put in the agent config. The *metric* the agent emits is
`nvidia_smi_utilization_gpu` (namespace `CWAgent` by default). The scaling policy
must reference the emitted name and whatever namespace we render, not the
measurement key.

Collection requires an NVIDIA driver on the host. The module already boots the
GPU-optimized ECS AMI when `gpu_count > 0` (`locals.tf` `selected_ami`), which ships
the driver, so `nvidia-smi` is present. On a non-GPU AMI the collector fails to
start — collection must be gated on `gpu_count > 0`.

This plan does not touch PR #171. Prometheus scraping stays as an independent,
opt-in path; GPU-native scaling is a separate opt-in.

### Decided: the scaling policy sits inside the module

The policy lives **inside the module**, consistent with how the module already owns
its target-tracking policy (`autoscaling.tf`) and with the self-contained pattern
used for `extra_target_groups`. Metric *collection* belongs inside regardless.
Keeping the policy inside means a consumer flips one flag instead of hand-wiring a
custom-metric policy against internals it would otherwise have to import (the
scalable target `resource_id`, the `AutoScalingGroupName` value `local.asg_name`,
and `local.gpu_metrics_namespace`).

Two consequences for implementation:

- **Additive, and keeping the CPU policy is deliberate.** Application Auto Scaling
  permits multiple target-tracking policies on one scalable target — scale-out takes
  the max across policies, scale-in only when *all* agree. So the GPU policy is a
  *second* `aws_appautoscaling_policy` gated on `gpu_count > 0`, leaving the existing
  `ecs_policy` (CPU/ALB) in place — not a branch inside it. The service therefore
  scales on **GPU and CPU together**: whichever resource saturates first adds tasks,
  and a task is removed only when both are slack. This is what handles the
  CPU-bound-but-GPU-idle case (see 1b) — dropping the CPU policy would leave a
  CPU-saturated service unable to scale. The "additive is bad" caution applies only
  to the *instance* layer (1c), never here.
- **Escape hatch via outputs.** For consumers who outgrow the single-target
  policy (metric math, step scaling, blending GPU with app metrics), expose the
  building blocks as outputs — the appautoscaling target `resource_id`, the ASG name,
  and the namespace — so they can build a custom policy alongside it. Default path is
  the built-in GPU policy; advanced path is outputs.

---

## Problem 1 — Scale on GPU utilization

### 1a. Emit the GPU metric (CloudWatch agent)

The default agent config template (`assets/cloudwatch_agent_config.tftmpl`) is
logs-only today. Add an `nvidia_gpu` metrics block, gated on GPU workloads.

The namespace is rendered from a single local (`local.gpu_metrics_namespace = "CWAgent"`)
so the template and the scaling policy (1b) never drift. It is a local, not an input
variable — the value is fixed and consumers should not change it; DRY here means one
source of truth, not one more knob. The template receives it via `templatefile()`;
the policy reads the same local.

```json
"metrics": {
  "namespace": "${gpu_metrics_namespace}",
  "append_dimensions": {
    "AutoScalingGroupName": "${aws:AutoScalingGroupName}"
  },
  "aggregation_dimensions": [["AutoScalingGroupName"]],
  "metrics_collected": {
    "nvidia_gpu": {
      "measurement": ["utilization_gpu", "memory_used", "memory_total"],
      "metrics_collection_interval": 60
    }
  }
}
```

Why `append_dimensions` + `aggregation_dimensions`: `nvidia_smi_utilization_gpu` is
per-instance (and per-GPU `index`). Target tracking needs one aggregated time
series. Rolling the metric up to `AutoScalingGroupName` gives a single fleet-wide
series the policy can average over. Without it, the policy has no fleet-level value
to track.

Rendering (decided): extend the existing `templatefile()` selection in
`datasources.tf` so a GPU variant of the template is chosen when **`gpu_count > 0`**,
mirroring how the Prometheus template is selected today. No `render_gpu_metrics`
flag is threaded into a shared template. Pass `local.gpu_metrics_namespace` into the
`templatefile()` vars so the namespace is not a literal in the template.

Everything GPU is gated on the single condition `gpu_count > 0` — both metric
collection (here) and the scaling policy (1b). There is no separate feature flag:
if the service runs on GPU hardware, it collects GPU metrics and scales on them.
The driver only exists on the GPU AMI, so `gpu_count > 0` is also the correctness
boundary for collection.

Note the three-way precedence already in `datasources.tf`: an explicit
`cloudwatch_agent_config` override wins, then the Prometheus template, then the
default. The GPU variant has to slot into that selection without breaking the
byte-identical default for non-GPU consumers.

Open sub-question for implementation: how the GPU variant composes with the existing
**Prometheus** template — if a consumer sets `gpu_count > 0` *and* enables Prometheus
scraping, one selection has to win or the two metric blocks have to merge. Resolve
during implementation; simplest is a defined precedence (e.g. GPU variant is a
superset that also carries the Prometheus block when both apply).

### 1b. Scale the ECS service on that metric (`autoscaling.tf`)

`autoscaling.tf` today only supports `predefined_metric_specification`
(`ECSServiceAverageCPUUtilization`, `ALBRequestCountPerTarget`, …). GPU utilization
is a custom CloudWatch metric, so add a **second** `aws_appautoscaling_policy`
resource (gated on `gpu_count > 0`) with a `customized_metric_specification`,
leaving `ecs_policy` untouched — the two target-tracking policies coexist on the same
scalable target:

```hcl
target_tracking_scaling_policy_configuration {
  customized_metric_specification {
    metric_name = "nvidia_smi_utilization_gpu"
    namespace   = local.gpu_metrics_namespace
    statistic   = "Average"
    dimensions {
      name  = "AutoScalingGroupName"
      value = local.asg_name
    }
  }
  target_value       = var.gpu_autoscaling_target   # e.g. 60 (percent)
  scale_in_cooldown  = 300
  scale_out_cooldown = 300
}
```

The lever stays the ECS **service desired count** (`aws_appautoscaling_target.ecs_target`,
`ecs:service:DesiredCount`), not the ASG directly. The loop:

GPU utilization rises → target tracking raises desired task count → each task
reserves `gpu_count` GPUs → the capacity provider (managed scaling,
`target_capacity = 100` in `main.tf`) launches more GPU instances to place them.
Scale-in reverses it, bounded by the floor in Problem 2.

If `AutoScalingGroupName` aggregation proves too coarse, the fallback is a
`customized_metric_specification` with a `metrics` (metric-math) block averaging
across `InstanceId`. Start with the aggregated single metric; only reach for metric
math if needed.

Namespace comes from `local.gpu_metrics_namespace` (= `"CWAgent"`) in both 1a and
1b, so they cannot drift — the template gets it as a `templatefile()` argument and
the policy reads the local directly. Changing the namespace is a one-line edit in
`locals.tf`.

**Why the CPU service policy stays (the CPU-bound / GPU-idle case).** A GPU service
can be bottlenecked on host CPU (tokenization, request handling) while GPU has
headroom — e.g. 90% CPU / 20% GPU on two tasks. Autoscaling's job is availability:
the CPU service policy adds tasks so load spreads (→ ~45% CPU / ~10% GPU on four
tasks) and the service stays responsive. The now-idle GPU is *information*, not a
failure — surfaced on the dashboard (Problem 3) so the operator can decide whether a
same-GPU / beefier-CPU instance type is more cost-efficient. The policy keeps the
service alive; the human makes the efficiency call from data. Critically this works
because **adding a task genuinely relieves service CPU** (the new replica takes a
share of requests) — unlike adding an *instance*, which does not (1c).

---

### 1c. Do NOT scale instances on host CPU — neutralize website-pod's `cpu_load`

`website-pod` unconditionally attaches `aws_autoscaling_policy.cpu_load`
(`ASGAverageCPUUtilization`, target `var.autoscaling_target_cpu_load`) to the ASG
(`.terraform/modules/pod/autoscaling.tf`). So every ECS ASG already has **two**
controllers on its desired capacity: `cpu_load` (host CPU) and ECS managed scaling
(`CapacityProviderReservation`, `target_capacity = 100`).

For GPU workloads `cpu_load` is actively harmful. Host CPU cannot be relieved by
adding an instance — ECS does not migrate a running task onto new capacity, and task
count is GPU/CPU-*service*-driven, not host-driven. So on high host CPU, `cpu_load`
launches instances ECS has no task for; they idle, don't relieve CPU, merely dilute
the `ASGAverageCPUUtilization` average, and fight managed scaling (which wants them
gone). AWS explicitly warns against a custom ASG policy alongside managed scaling —
the steady state is undefined (idle-cost or flapping). The task-vs-instance split:

| | Add a **task** (service CPU policy, 1b) | Add an **instance** (`cpu_load`) |
|---|---|---|
| Relieves CPU? | Yes — replica takes a request share | No — task doesn't move |
| Target tracking converges? | Yes, real negative feedback | No, only by diluting the average |

Fix: neutralize `cpu_load` for GPU so **managed scaling (reservation) is the sole
instance driver**. Two options:

- **Now, no submodule change:** in `website-pod.tf`, pass a never-fires target for
  GPU — `autoscaling_target_cpu_load = var.gpu_count > 0 ? 99 : var.autoscaling_target_cpu_usage`.
  The policy still exists but never triggers.
- **Later, cleaner:** add a toggle in `website-pod` to not create `cpu_load` at all,
  set off for GPU (rides with the ODCR submodule change in Problem 2).

Watch the coupling: `var.autoscaling_target_cpu_usage` is **double-duty** — it feeds
both the ECS *service* CPU policy (1b) and, via `website-pod.tf`, the ASG `cpu_load`
target. The GPU override must fork only the ASG side, leaving the service CPU target
intact.

---

## Problem 2 — Preserve minimum GPU capacity (ODCR)

Goal: production always has at least N GPU instances available, reserved via ODCR,
and autoscaling never scales the fleet below that floor.

The ASG and its launch template live in the **`website-pod` submodule**
(`registry.infrahouse.com/infrahouse/website-pod/aws`, v6.2.0), not in this repo.
`website-pod.tf` already passes `on_demand_base_capacity`, `asg_min_size`,
`asg_max_size`, and sets `protect_from_scale_in = true` (ECS manages instances).
ODCR association happens on the launch template, so this likely needs a change in
`website-pod` plus a pass-through here.

Two ways to bind the ASG to the reservation:

- **Open ODCR** — create the reservation with `instance_match_criteria = "open"`;
  any matching `g5.2xlarge` launched in the AZ consumes it automatically. Least
  plumbing; no launch-template change strictly required, but capacity is only
  guaranteed if the ASG's AZ/instance type match the reservation exactly.
- **Targeted ODCR** — `instance_match_criteria = "targeted"` and point the launch
  template at it via `capacity_reservation_specification { capacity_reservation_target { capacity_reservation_id | capacity_reservation_resource_group_arn } }`.
  Deterministic, and the recommended path when the reservation must not be consumed
  by anything else. Requires `website-pod` to expose a launch-template capacity
  reservation input.

Floor mechanics, independent of which binding:

- Keep `asg_min_size` ≥ reserved instance count so scale-in never drops below the
  reservation. `asg_min_size` is auto-derived by `modules/scaling` today, so either
  raise the derived floor for GPU or let the consumer set it explicitly (both are
  already supported inputs).
- Set `task_min_count` so the always-on task count keeps at least the reserved
  instances busy/occupied.
- `on_demand_base_capacity` (already plumbed) guarantees the base is on-demand
  rather than spot.

### Dependency / decision to confirm

**Confirmed (checked `.terraform/modules/pod`, v6.2.0):** website-pod exposes **no**
capacity-reservation input — no `capacity_reservation` string anywhere, and the
launch template (`asg.tf:83`) has no `capacity_reservation_specification` block. So:

- **Targeted ODCR** requires a website-pod change first (add a
  `capacity_reservation_specification` dynamic block to `aws_launch_template.website`
  plus a variable to pass the reservation id/ARN), then a pass-through here. This is
  the same submodule-PR dependency as the `cpu_load` toggle (1c) — bundle them.
- **Open ODCR** works today with no submodule change (matches by AZ + instance type),
  at the cost of a weaker guarantee (any matching instance in the AZ can consume it).

Still to decide: open vs targeted, and whether the module *creates* the
`aws_ec2_capacity_reservation` or just consumes a consumer-supplied ID/ARN — leaning
toward consumer-supplied, so the module stays a consumer, not an owner, of the
reservation.

---

## Problem 3 — Observability so the operator can judge efficiency

Autoscaling keeps the service *available*; it cannot tell you whether the instance
type is *cost-efficient*. The CPU-bound / GPU-idle signature (Problem 1b) is the
prime example: the service scales out and stays healthy, but the fleet may be running
GPUs mostly to buy CPU headroom. That is a legitimate steady state — it just needs to
be **visible** so a human can decide whether a same-GPU / beefier-CPU (or fewer-GPU)
instance type would be cheaper. Scaling ensures uptime; the dashboard informs the
sizing decision.

Add a CloudWatch dashboard (gated on `gpu_count > 0`) that puts the relevant series
side by side so the signature is readable at a glance:

- **GPU utilization** (`nvidia_smi_utilization_gpu`, by ASG) — the task signal.
- **Service CPU utilization** (`ECSServiceAverageCPUUtilization`) — the other task
  signal; the two together show which resource is driving scale-out.
- **GPU memory used / total** (already collected in 1a) — headroom / OOM proximity.
- **Running task count** and **ASG instance count** — how scaling responded.
- Optionally the two policies' target lines (GPU target, CPU target) for context.

The read the dashboard is built to make obvious: *"GPU sits at 10% while CPU pins at
45% across four tasks / four GPUs"* → the operator sees they are paying for idle GPU
and can evaluate a CPU-richer instance. No alarm, no auto-action — just data.

Keep it a plain `aws_cloudwatch_dashboard` in this module, gated like everything else
on `gpu_count > 0`, so non-GPU consumers get nothing new.

Metric availability is already satisfied — no website-pod change needed: `asg_name`
comes from `local.asg_name` (website-pod output), and the ASG instance-count series
(`AWS/AutoScaling` `GroupInServiceInstances` / `GroupTotalInstances`) is published by
default because website-pod's `asg_enabled_metrics` default already enables them.

---

## Scope of Changes

### terraform-aws-ecs

| File | Change |
|------|--------|
| `assets/cloudwatch_agent_config.tftmpl` (or a new GPU variant) | Add gated `nvidia_gpu` metrics block with append/aggregation dimensions |
| `datasources.tf` | Slot GPU metric rendering into the existing agent-config template selection; pass `local.gpu_metrics_namespace` into the template vars |
| `locals.tf` | Add `gpu_metrics_namespace = "CWAgent"` — single source of truth for both the template and the scaling policy |
| `autoscaling.tf` | Add a second gated `aws_appautoscaling_policy` (GPU `customized_metric_specification`); leave `ecs_policy` (CPU) in place so the service scales on GPU + CPU |
| `website-pod.tf` | Neutralize `cpu_load` for GPU: `autoscaling_target_cpu_load = var.gpu_count > 0 ? 99 : var.autoscaling_target_cpu_usage` (managed scaling becomes the sole instance driver). Plus ODCR pass-through (if targeted path) |
| `cloudwatch.tf` (or new `dashboard.tf`) | Add gated `aws_cloudwatch_dashboard`: GPU util, service CPU, GPU memory, task count, instance count (Problem 3) |
| `outputs.tf` | Expose appautoscaling target `resource_id`, ASG name, and `gpu_metrics_namespace` as the escape hatch for consumer-built policies |
| `variables.tf` | `gpu_autoscaling_target`, ODCR pass-through (id/ARN) |
| `locals.tf` / `modules/scaling` | Ensure `asg_min_size` floor ≥ reserved GPU count |
| `test_data/` + `tests/` | GPU fixture is expensive; see testing note |

### website-pod (separate module, may be required)

| File | Change |
|------|--------|
| launch template | Expose `capacity_reservation_specification` input (targeted ODCR path only) |

### Not changing

- PR #171 Prometheus path — stays independent and opt-in.
- `modules/tcp-pod` — unless NLB GPU services are in scope (not requested).

---

## Proposed variables

```hcl
variable "gpu_autoscaling_target" {
  description = "Target average GPU utilization (percent) for the target-tracking policy."
  type        = number
  default     = 60
}

variable "gpu_capacity_reservation_id" {
  description = "Optional On-Demand Capacity Reservation to back minimum GPU capacity. When set, the ASG launch template targets this reservation and the ASG floor is held at or above its reserved count."
  type        = string
  default     = null
}
```

Names are a starting point; align with existing `autoscaling_*` naming during review.

---

## Usage example

```hcl
module "qwen_short" {
  source  = "registry.infrahouse.com/infrahouse/ecs/aws"
  version = "X.Y.Z"

  service_name   = "qwen-short"
  docker_image   = "..."
  container_port = 8000

  gpu_count         = 1
  asg_instance_type = "g5.2xlarge"

  enable_cloudwatch_logs = true
  gpu_autoscaling_target = 60   # GPU scaling is automatic when gpu_count > 0

  task_min_count = 1
  task_max_count = 4

  gpu_capacity_reservation_id = "cr-0123456789abcdef0"

  # ... other required variables ...
}
```

---

## Version impact

**Non-GPU consumers (`gpu_count = 0`):** no change. The GPU template variant and the
GPU policy are both gated on `gpu_count > 0`, so their rendered config stays
byte-identical — confirm this in testing.

**Existing GPU consumers (`gpu_count > 0`):** this is *not* a no-op for them. Because
GPU scaling is unconditional (no opt-in flag), upgrading adds a GPU metrics block to
their agent config *and* a second target-tracking policy to their service. Their
service will begin scaling on GPU utilization after the upgrade. That is a behavior
change on a minor bump — call it out prominently in the CHANGELOG, and consider
whether it warrants a **major** bump instead. Decision to confirm at implementation:
minor with a loud CHANGELOG note vs. major.

---

## Checklist

- [x] Confirmed: `website-pod` v6.2.0 exposes **no** capacity-reservation input
      (no `capacity_reservation` anywhere; launch template `asg.tf:83` has no
      `capacity_reservation_specification`). → Targeted ODCR needs a submodule change;
      Open ODCR works today. **Decide open vs targeted.**
- [x] Policy placement: **inside the module**, as a second additive
      `aws_appautoscaling_policy` (decided)
- [ ] Add outputs (target `resource_id`, namespace) as the escape hatch —
      note `asg_name` is **already** output (`outputs.tf:26`, from website-pod's
      `asg_name`) and available as `local.asg_name` (`locals.tf:82`)
- [ ] Add gated `nvidia_gpu` block to the agent config template
- [ ] Wire GPU template rendering into `datasources.tf` selection
- [ ] Add second gated `aws_appautoscaling_policy` (GPU `customized_metric_specification`);
      keep `ecs_policy` (CPU) so the service scales on GPU + CPU
- [ ] Neutralize `cpu_load` for GPU in `website-pod.tf` (`autoscaling_target_cpu_load
      = gpu_count > 0 ? 99 : var.autoscaling_target_cpu_usage`); managed scaling is the
      sole instance driver — no host-CPU ASG policy
- [ ] Add gated `aws_cloudwatch_dashboard` (GPU util, service CPU, GPU memory, task
      count, instance count) so the CPU-bound/GPU-idle signature is visible (Problem 3)
- [ ] Add variables (`gpu_autoscaling_target`, ODCR id) — no on/off flag; GPU
      scaling is gated on `gpu_count > 0`
- [ ] Enforce `asg_min_size` floor ≥ reserved GPU count
- [ ] Add `local.gpu_metrics_namespace` and reference it from both the template
      (via `templatefile()` vars) and the scaling policy — no hardcoded `"CWAgent"`
- [ ] Verify emitted metric name/namespace matches the scaling policy reference
- [ ] `terraform fmt -recursive`, `make validate`
- [ ] Read `.claude/CODING_STANDARD.md` before writing any code
- [ ] Testing: GPU integration test is costly — validate template rendering and
      `terraform validate` offline; run a live GPU test in sandbox before merge
      (mirrors #171's deferred live-GPU test)
