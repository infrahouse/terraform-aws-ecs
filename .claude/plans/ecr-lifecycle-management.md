# ECR Smart Lifecycle Management Plan

## Context

The original proposal was a complex system (DynamoDB, EventBridge,
Lambda, account-wide module looping over ECS clusters). After
discussion, we're taking a simpler two-module approach using the
existing ECR and ECS modules.

## Key Decisions

### 1. Two modules, not three

Only two modules are involved:
- **terraform-aws-ecr** — lifecycle rules that protect deployed images
- **terraform-aws-ecs** — EventBridge + Lambda that tags images after
  successful deployment

No separate lifecycle/tracker module.

### 2. Rollback candidate definition

A **rollback candidate** = an image that was successfully deployed to
an ECS service at least once.

### 3. Same-account assumption

ECR and ECS are always in the same AWS account. No cross-account
repo policies needed. The ECS module's Lambda just needs IAM
permissions on ECR repos in the same account.

### 4. Tag-based convention bridges ECR and ECS

ECR lifecycle policies are tag-pattern based — they can't know whether
an image was deployed. A tagging convention bridges the gap:
both modules agree on a tag prefix (`deployed-at-`). Images with
this prefix are rollback candidates.

## Architecture

### ECR Module (this repo) — Lifecycle Rules

Extends the existing lifecycle policy with rules that treat
rollback candidates (`deployed-at-*` tagged images) differently:

- **Rollback candidates**: retained longer / higher count
- **Non-deployed tagged images**: expired more aggressively
- **Untagged images**: existing behavior unchanged

New variables:
- `rollback_candidate_tag_prefix` — tag prefix identifying
  rollback candidates (default: `"deployed-at-"`)
- `rollback_candidate_retain_count` — how many rollback
  candidates to keep (default: `null`)
- `rollback_candidate_retain_days` — how long to keep rollback
  candidates (default: `null`)

New dynamic rule blocks in `policy.tf` with appropriate priorities.

**Backward compatibility**: All new variables default to `null`.
No rollback candidate rules are created unless
`rollback_candidate_retain_count` or
`rollback_candidate_retain_days` is explicitly set. Existing ECR
repos upgrading to the new module version see zero behavior change.
The feature is fully opt-in.

### ECS Module (terraform-aws-ecs) — Deployment Tagging

After a successful deployment, the ECS module tags the deployed image
in ECR so lifecycle rules can identify it as a rollback candidate.

**Mechanism: EventBridge + Lambda**

1. **EventBridge rule** catches `ECS Service Action` events with
   `SERVICE_STEADY_STATE` detail type (service reached steady state,
   all tasks healthy, desired count met)
2. **Lambda** triggers and:
   - Extracts service/cluster from the event
   - Calls `DescribeServices` → gets active task definition ARN
   - Calls `DescribeTaskDefinition` → gets image URI
     (ECR repo + tag/digest)
   - Detects whether the image is from ECR or a third-party registry
     (e.g., `grafana:latest`) — skips tagging if not ECR
   - Calls ECR `PutImage` to add a tag like
     `deployed-at-<YYYY-MM-DDTHH-MM-SSZ>` to the image manifest

**Lambda IAM permissions** (same account, no cross-account needed):
- `ecs:DescribeServices`
- `ecs:DescribeTaskDefinition`
- `ecr:BatchGetImage`
- `ecr:PutImage`
- `ecr:DescribeImages`

**Why this works well**:
- Event-driven, no polling
- `SERVICE_STEADY_STATE` is authoritative — ECS considers the
  deployment successful (health checks passed)
- Works regardless of how deployment was triggered (CodePipeline,
  CLI, Terraform, GitHub Actions, etc.)
- Third-party images are detected and skipped automatically

## Implementation Steps

### Step 1: Extend ECR module with deployed-image lifecycle rules

Add new variables and dynamic rule blocks in `policy.tf` that
protect rollback candidates (`deployed-at-*` tagged images) with
separate retention settings.

### Step 2: Tagging convention

Convention: `deployed-at-<YYYY-MM-DDTHH-MM-SSZ>`

The prefix must match between ECR module's
`rollback_candidate_tag_prefix` variable and the ECS module's
Lambda tagging logic. Default: `deployed-at-`.

### Step 3: Add EventBridge + Lambda to ECS module

In `terraform-aws-ecs`, create:
- EventBridge rule scoped to the module's own ECS service
- Lambda function that looks up the deployed image and tags it in ECR
- IAM role with minimal permissions

### Step 4: No DynamoDB needed

ECR image tags serve as the deployment record. No external state
store required.

## Open Questions

- Priority ordering of lifecycle rules when rollback candidate
  rules coexist with existing expire_* rules
- Whether the ECS module needs to accept the ECR repo ARN as input
  or can derive it from the task definition image URI
- How to handle images referenced by digest (no tag) in task
  definitions
