# ECS Rolling Deployment Capacity Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Size ECS capacity from whole task slots and guarantee that every configured desired count can make a
rolling-deployment move.

**Architecture:** Keep all math in the provider-free `modules/scaling` submodule. Pass the existing autoscaling range
and ECS deployment percentages into it, calculate the exact task-slot requirement, and reject impossible resource or
explicit-cap configurations with output preconditions. Preserve the automatic one-host scaling margin above the ASG
minimum. Set ux-labs production's temporary ceiling to the calculated 11 hosts.

**Tech Stack:** Terraform 1.9+, Terraform native tests, AWS ECS/Auto Scaling

---

### Task 1: Pin the capacity invariant with failing tests

**Files:**
- Modify: `tests/math.tftest.hcl`

1. Add the new inputs to the shared test defaults.
2. Add cases for a partially filled final host, a completely full fleet, and a stop-first deployment.
3. Add failure cases for an immovable deployment, a task too large for CPU or memory, and an undersized explicit ASG
   maximum.
4. Run `terraform test -test-directory=tests` and confirm the new cases fail for the intended reasons.

### Task 2: Implement exact task-slot capacity

**Files:**
- Modify: `scaling.tf`
- Modify: `modules/scaling/variables.tf`
- Modify: `modules/scaling/main.tf`
- Modify: `modules/scaling/outputs.tf`

1. Pass `task_min_count` and both deployment percentages into the internal module.
2. Calculate whole CPU, memory, and GPU slots without hiding a zero-slot instance.
3. Validate that each desired count in the autoscaling range permits either one stop-first or one start-first move.
4. Size the ASG for `task_max_count` plus one task only when the maximum-count rollout cannot stop first.
5. Reject an explicit maximum below the calculated requirement.
6. Run the native test suite and confirm all cases pass.

### Task 3: Make the production ceiling match the invariant

**Files:**
- Modify: `aws-control-ux-labs/.worktrees/ecs-rollout-capacity/environments/production/main.tf`

1. Change `frontend_asg_max_size` from 10 to 11.
2. Document the calculation next to the override.
3. Run Terraform formatting and validate with Terraform 1.9+.

### Task 4: Document and verify the final behavior

**Files:**
- Modify: `variables.tf`
- Regenerate: `README.md`

1. Describe task-slot deployment headroom and the explicit-cap constraint.
2. Run Terraform formatting and the provider-free native tests in Terraform 1.9+.
3. Inspect both repository diffs and confirm they contain only the shared invariant and the production 10-to-11 change.
