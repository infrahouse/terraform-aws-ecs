# CI test-runtime reduction plan

Status: proposed / not started
Author: analysis of the `make test` integration suite
Source run: PR #161 CI — GitHub Actions run `27482657531`, job `81233032275`
(`8 passed in 13089.06s (3:38:09)`).

## Problem

`make test` (CI step "Terraform Tests" in `.github/workflows/terraform-CI.yml`,
`pytest -xvvs tests/`) takes **~3h38m**. It runs 8 sequential, real-infrastructure
integration tests, each doing a full `terraform apply` (ECS cluster + ALB/NLB +
ASG + ACM/DNS + wait-for-healthy) followed by `destroy`.

Compounding factor: the workflow's `concurrency: group: aws-control,
cancel-in-progress: false` serializes runs repo-wide, so a 3h38m job blocks every
other PR's CI behind it.

## Per-test wall time (derived from GitHub Actions log timestamps)

| # | Test | Duration |
|---|------|----------|
| 1 | `test_httpd` (ALB happy path) | ~33m |
| 2 | `test_httpd_autoscaling[ALBRequestCountPerTarget-100-aws-6]` | ~29m |
| 3 | `test_httpd_autoscaling[ECSServiceAverageMemoryUtilization-...-aws-6]` | ~29m |
| 4 | `test_httpd_autoscaling[ECSServiceAverageCPUUtilization-70-aws-6]` | ~29m |
| 5 | `test_httpd_ecr_tagger` | ~31m |
| 6 | `test_httpd_efs` | ~7m |
| 7 | `test_httpd_tcp` (NLB) | ~29m |
| 8 | `test_tempo_grpc` (gRPC target group) | ~31m |

Total ≈ 3h38m, fully serial. Session-scoped `service_network` / `subzone`
fixtures are created once (not the bottleneck); the per-test cost is the ECS
stack apply + steady-state wait + destroy.

## #1 finding: autoscaling is ~87 min of largely redundant coverage

`test_httpd_autoscaling` is parametrized into 3 variants
(`ALBRequestCountPerTarget`, `ECSServiceAverageMemoryUtilization`,
`ECSServiceAverageCPUUtilization`) — **~87 minutes combined (~25% of the run)**.
All three stand up the *same* full ECS+ALB+ASG stack and differ only by the
`autoscaling_metric` value. They verify **config wiring** (that the correct
`aws_appautoscaling_policy` / target-tracking config is produced per metric), not
runtime scaling — nothing in the run drives load to trigger a scale event.

This is exactly what belongs in a plan-only `terraform test` (the same pattern
now used for the ASG sizing math in `tests/math.tftest.hcl`): assert each metric
produces the right policy at ~0 cost and with no AWS.

## Recommendations (highest -> lowest value)

1. **Autoscaling: 3 live applies -> 1 (or 0).** Move the per-metric assertions to
   a `*.tftest.hcl` (`command = plan`, no AWS). Keep at most one apply-based
   autoscaling smoke test (or drop it entirely if the plan tests cover the wiring).
   **Saves ~57-87 min** -> total drops to roughly **2h10m-2h40m**. Biggest,
   lowest-risk win. ~1 hour of work, minimal coverage loss.
2. **Reassess full-apply necessity for config-only assertions.** Most of each
   29-33 min is `wait_for_success` + steady-state convergence + destroy. Tests
   that only assert on created resources/outputs (not live HTTP) don't strictly
   need the service to reach healthy steady state — but removing the apply loses
   real integration coverage, so do this selectively, not wholesale.
3. **`test_httpd_efs` (~7m) is already cheap** — leave it.

## What NOT to skip (distinct code paths)

- `test_httpd` — ALB happy path (`website-pod` submodule).
- `test_httpd_tcp` — NLB path (`tcp-pod`, a *different* submodule).
- `test_tempo_grpc` — gRPC target group.
- `test_httpd_ecr_tagger` — the `lambda-monitored` ECR image-tagger (distinct feature).

Keep one full apply per distinct path.

## Other levers (lower priority)

- **Parallelization (pytest-xdist `-n`)** could cut wall time, but the
  session-scoped shared `service_network`/`subzone` fixtures plus real AWS infra
  make concurrent applies risky/complex. Cutting redundant applies is the better
  lever first.
- **Skip `destroy` in CI?** Destroy is ~half of each test's time, but it
  validates clean teardown (and leaves no orphaned infra) — not recommended to
  remove.

## Suggested first step

Implement recommendation #1: add an autoscaling `*.tftest.hcl` (plan-only,
per-metric policy assertions) and reduce live `test_httpd_autoscaling` to a single
representative variant (or remove it). Re-measure; expect ~1h saved.
