# ECS Rolling Deployment Capacity Design

## Problem

The module currently treats fractional CPU and memory capacity as schedulable and sizes `asg_max_size` for
steady state only. ECS tasks cannot span instances, and a rolling deployment with
`deployment_minimum_healthy_percent = 100` must place a replacement before stopping an old task. A service at its
task and ASG maximum can therefore deadlock even though its steady-state fleet fits.

The ux-labs frontend demonstrates both defects. A `t3.xlarge` has 14,848 MiB available after the module's OS and
daemon reservations. A 5,120 MiB task fits twice, not 2.9 times. Twenty steady-state tasks require ten hosts, and a
start-first rollout requires at least one additional task slot.

## Approved invariant

For each desired task count, ECS must be able to make a first deployment move: either stop one old task without
crossing the minimum healthy count or start one replacement without crossing the maximum running count.

For the maximum task count `T`:

```text
memory_slots = max(1, floor((instance_memory - OS_memory - daemon_memory) / task_memory_reservation))
cpu_slots    = floor((instance_cpu - daemon_cpu) / task_cpu)
gpu_slots    = floor(instance_gpus / task_gpus) when GPUs are requested
S            = minimum active whole-resource slot count

minimum_healthy = ceil(T * deployment_minimum_healthy_percent / 100)
maximum_running = floor(T * deployment_maximum_percent / 100)
can_stop_first  = minimum_healthy <= T - 1
can_start_first = maximum_running >= T + 1

required_slots        = T when can_stop_first, otherwise T + 1
required_instances    = max(asg_min_size, ceil(required_slots / S))
automatic_asg_max_size = max(required_instances, asg_min_size + 1)
```

The one-task memory floor preserves the module's small-instance behavior: the 1 GiB OS value is conservative packing
headroom, not an ECS reservation. Planning still fails if task and daemon reservations leave no host memory, if
CPU/GPU reservations cannot fit, if neither a stop-first nor start-first move is allowed for any desired
count in the configured autoscaling range, or if an explicit ASG maximum cannot supply the required slots.
The automatic maximum retains one host above `asg_min_size` so the existing host-CPU scaling policy can scale out;
an explicit maximum may intentionally omit that optional scaling headroom but may not omit required task slots.

For ux-labs, `T = 20`, `S = 2`, minimum healthy is 20, and maximum running is 40. The required capacity is therefore
21 task slots and `ceil(21 / 2) = 11` instances.

## Module seam

Keep the calculation behind the existing ASG-sizing module. Pass the existing task-count and deployment-percentage
inputs into that internal module; do not add a new public headroom setting. The existing `asg_max_size` override
remains the cost-control interface, but an override that contradicts the declared task and deployment configuration
must fail planning instead of producing an ECS deadlock.

## Production rollout

Set the current ux-labs production override from 10 to 11 immediately. This changes the ASG ceiling, not its minimum
or desired size. The capacity provider may launch the eleventh host while replacements are pending and scale it back
after the rollout.

After the corrected shared module is released and adopted, remove the ux-labs override so the tested calculation is
the source of truth.

## Release compatibility

Rejecting an explicit maximum below the declared task/deployment requirement changes the public override contract.
Release the shared-module validation in the next major version and migrate exact-pinned consumers deliberately; the
ux-labs value of 11 can ship independently against 8.4.0.

## Alternatives rejected

- Lowering the shared minimum healthy percentage weakens availability and can still deadlock after ECS percentage
  rounding.
- Lowering the deployment maximum does not create a free slot on a full ASG.
- Keeping permanent spare instances through a lower capacity-provider target creates ongoing cost when a temporary
  deployment ceiling is sufficient.

## Verification

- Provider-free Terraform tests cover whole CPU, memory, and GPU slots; exact-full and partial-host fleets; deployment
  percentage rounding; zero-slot tasks; and valid and invalid explicit ASG caps.
- The ux-labs production plan changes only the frontend ASG maximum from 10 to 11.
- A production rollout at desired count 20 reaches one stable deployment with 20 running, zero pending, and the old
  revision drained.

Waiting for ECS service stability in CI is a separate observability improvement and is not part of this capacity fix.
