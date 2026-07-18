# GPU Utilization Autoscaling Plan

**Module:** terraform-aws-ecs
**Status:** policy + dashboard + ODCR shipped in **8.3.0**; GPU metric collection was
broken there (container couldn't see the GPU) and is fixed by the **host-agent**
approach on branch `feat/issue-173-gpu-agent-runtime` (builds on #174, closes #173).
**Related:** #173 (issue), #174 (@kendrickpham-tinyfish env passthrough), PR #171
(Prometheus scraping — independent), Slack "Discuss Autoscaling For GPU Instance"
**Blog:** https://infrahouse.com/blog/2026-06-14-serving-a-7b-model-on-ecs-gpu/ (a
war-story follow-up on the host-agent saga is planned — see "Dead ends" in 1a)
**Last Updated:** 2026-07-18

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

### 1a. Emit the GPU metric — host CloudWatch agent (NOT the sidecar)

**Final, shipped decision: GPU metrics are collected by a host-level CloudWatch
agent, not the containerized cloudwatch-agent daemon.** This was hard-won — the
original container-based approach (8.3.0) never actually worked. See "Dead ends" below.

The host has native `nvidia-smi` (it boots the GPU AMI). On `gpu_count > 0`, user_data
(`datasources.tf`) writes a host agent config and installs + starts it as a systemd
service (`dnf install -y amazon-cloudwatch-agent` + `amazon-cloudwatch-agent-ctl -a
fetch-config`), independent of docker/ecs. It emits exactly the series the policy tracks:

```json
{
  "metrics": {
    "namespace": "CWAgent",
    "append_dimensions": { "AutoScalingGroupName": "${aws:AutoScalingGroupName}" },
    "aggregation_dimensions": [["AutoScalingGroupName"]],
    "metrics_collected": {
      "nvidia_gpu": {
        "measurement": ["utilization_gpu", "memory_used", "memory_total"],
        "metrics_collection_interval": 60
      }
    }
  }
}
```

- Namespace is `local.gpu_metrics_namespace = "CWAgent"` — one source of truth shared
  with the policy (1b).
- `append_dimensions` + `aggregation_dimensions` roll the per-instance metric up to a
  single `AutoScalingGroupName` series that target tracking can average over.
- The instance role gets `cloudwatch:PutMetricData` (scoped to the CWAgent namespace) so
  the host agent can publish.
- The containerized cloudwatch-agent daemon stays **logs-only**.
- The metric name `nvidia_smi_utilization_gpu` (not the `utilization_gpu` measurement
  *key*) is what the policy references. Emitting host-side vs. sidecar is invisible to
  the policy and dashboard — same name/namespace/`AutoScalingGroupName` series.
- The host agent is intentionally **unpinned** (`dnf` pulls the AMI's latest), unlike the
  container logs agent pinned via `cloudwatch_agent_image` — a small reproducibility gap
  accepted because it's stock AWS tooling.

#### Dead ends (why not the sidecar) — the war story

The original plan put an `nvidia_gpu` block in the *containerized* agent's config.
**On the AL2023 ECS GPU-optimized AMI a container can only see the GPU when ECS assigns
it one via `resourceRequirements`.** Every attempt to give the unreserved agent
container GPU visibility failed, each verified on the live instance:

1. **8.3.0 — container `nvidia_gpu` config only.** The telegraf collector can't find
   `/usr/bin/nvidia-smi` inside the container, exits 1, crash-loops. Metric never
   publishes; the shipped dashboard + policy consume a phantom. Slipped through because
   the emission test (`make test-gpu`) was never run before the release.
2. **#174 — `NVIDIA_VISIBLE_DEVICES=all` + `NVIDIA_DRIVER_CAPABILITIES=utility` env vars.**
   Inert: the AMI registers the nvidia runtime but keeps docker `default-runtime = runc`,
   so an unreserved container runs under runc and the env vars do nothing.
3. **`default-runtime = nvidia`** (daemon.json). The container now runs on the nvidia
   runtime, but nvidia-smi is *still* not injected — the AL2023 toolkit (1.19, CDI/`auto`
   mode) doesn't honor `NVIDIA_VISIBLE_DEVICES` for unprivileged containers (tested `all`,
   the CDI name, the app's exact UUID, legacy mode, and the accept-envvar flag — all
   failed). Bonus trap: applying it via `runcmd` restarts docker, which propagates to
   `ecs.service` (`PartOf=docker.service`) and wedges the agent's startup — so it had to
   move to `write_files` (laid down before docker first starts) anyway.
4. **CDI** — `docker --device nvidia.com/gpu=all` (with `features.cdi=true`) also fails to
   inject, and ECS task definitions expose **no** way to request a CDI device regardless.

The only thing that injects the GPU is ECS's own assignment (`ECS_ENABLE_GPU_SUPPORT` +
`resourceRequirements`, which bind-mounts nvidia-smi + the driver libs). Reserving a GPU
for the sidecar is out — it would steal the GPU from the workload on single-GPU
instances. Hence: **collect on the host, where nvidia-smi is native.** (The
env-var/default-runtime path *did* work on the legacy AL2 GPU AMI — but that AMI is EOL
2026-06-30, so it's not a basis to build on.)

The guard that would have caught 8.3.0, and now does: the `make test-gpu` emission
assertion (`_wait_for_gpu_metrics`) waits for the real metric to land in CloudWatch. The
injection-based autoscaling test can't catch it — it publishes its own metric.

Everything GPU is gated on the single condition `gpu_count > 0` — both host-agent
collection (here) and the scaling policy (1b). No separate feature flag.

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

Two releases landed here. **8.3.0** shipped the policy + dashboard + ODCR + the
(broken) container metric collection. The **host-agent fix** (this branch, on top of
#174) makes the metric actually publish.

**8.3.0 (already released):**

| File | Change |
|------|--------|
| `locals.tf` | `gpu_metrics_namespace = "CWAgent"` — single source of truth for collection + policy |
| `autoscaling.tf` | Second gated `aws_appautoscaling_policy` (GPU `customized_metric_specification`); `ecs_policy` (CPU) stays → service scales on GPU + CPU |
| `website-pod.tf` | Bump to 6.3.0; `autoscaling_target_cpu_load = gpu_count > 0 ? null : ...` to drop the host-CPU ASG `cpu_load` policy (managed scaling becomes sole instance driver) |
| `dashboard.tf` | Gated `aws_cloudwatch_dashboard`: GPU util, service CPU, GPU memory, task count, instance count (Problem 3) |
| `outputs.tf` | Expose appautoscaling target `resource_id` + `gpu_metrics_namespace` (`asg_name` already existed) as the escape hatch |
| `variables.tf` | `gpu_autoscaling_target`, `gpu_capacity_reservation_id` |
| `validations.tf` | GPU guards: requires `enable_cloudwatch_logs`, `lb_type = alb`, reservation requires `gpu_count > 0` |
| `datasources.tf` | (8.3.0) container agent GPU-variant config — **later reverted**, never worked |

**Host-agent fix (this branch, on top of #174):**

| File | Change |
|------|--------|
| `datasources.tf` | Container agent → logs-only; on `gpu_count > 0` write a **host** CloudWatch agent config (`nvidia_gpu` collector) + `runcmd` install/start; add `cloudwatch:PutMetricData` to the instance role (namespace-scoped) |
| `locals.tf` | Add `gpu_host_agent_config_path`; drop #174's obsolete NVIDIA env default, keep its generic `cloudwatch_agent_extra_environment` passthrough |
| `assets/cloudwatch_agent_config_gpu.tftmpl` | **Deleted** (the container GPU config that couldn't work) |
| `tests/test_gpu.py` | Emission gate (`_wait_for_gpu_metrics`) + instance-refresh wait; drop the obsolete container-env assertion |
| `tests/conftest.py` | Configure the `pytest_infrahouse` logger so helper progress is visible |

**website-pod 6.3.0 (separate module, released):**

| File | Change |
|------|--------|
| launch template | `capacity_reservation_specification` input (targeted ODCR) |
| `autoscaling.tf` | `autoscaling_target_cpu_load` nullable → `null` skips the `cpu_load` policy (`moved` block preserves state) |

### Not changing

- PR #171 Prometheus path — stays independent and opt-in.
- `modules/tcp-pod` — GPU is ALB-only (validation enforces `lb_type = alb`).
- ODCR floor (`asg_min_size` ≥ reserved count) — left to the consumer; no
  `aws_ec2_capacity_reservation` data source exists to auto-read the count.

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
