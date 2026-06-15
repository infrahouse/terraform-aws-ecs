# Experiment 2 — vLLM GPU serving stack

A Terraform root module that stands up a small **GPU serving fleet** with the
parent `terraform-aws-ecs` module: two `g5.2xlarge` nodes (1×A10G each) that fetch
`Qwen/Qwen2.5-7B-Instruct` from Hugging Face and serve it with vLLM behind an ALB.

It exists to exercise the module's `gpu_count` path end-to-end and to prove a real
model answers over the load balancer. It is **not** part of CI.

## How it's used

This stack is driven by `tests/test_experiment2.py` (pytest marker `serving`), not
applied by hand. The test:

1. Builds the vLLM image (`docker/vllm/`, with `fetch_model.sh` baked in) and
   pushes it to a throwaway ECR repo.
2. Writes `terraform.tfvars` (subnets, zone, region, and the `docker_image` URI),
   then `terraform apply`s this stack.
3. Waits for vLLM `/health`, asserts the weights landed on disk, POSTs a real
   prompt to `/v1/chat/completions`, and asserts a well-formed completion.
4. `terraform destroy`.

Run it from the repo root:

```bash
make test-experiment2                 # ~$4/run; needs docker + a g5 GPU quota
make test-experiment2 KEEP_AFTER=1    # keep resources for debugging
```

The `service_network` / `subzone` pytest fixtures supply the VPC subnets and the
Route53 zone, so the stack is created in the same region as those fixtures
(`--aws-region`, default `us-west-2`).

## Serving contract

The container never runs `vllm serve <hf-repo-id>`. Its entrypoint
(`docker/vllm/entrypoint.sh`) runs:

```
fetch_model.sh hf://Qwen/Qwen2.5-7B-Instruct /models   # populate local disk
vllm serve /models/Qwen2.5-7B-Instruct --port 8000 ... # serve from local disk
```

so the weight source can change (HF today; a mirror, P2P, or Lustre later) without
touching the serving layer. Only the `FETCH_BACKEND=http` + `hf://` path is
implemented; other backends are stubs.

## Key inputs

| Variable | Default | Notes |
|----------|---------|-------|
| `docker_image` | (required) | ECR URI of the vLLM image; injected by the test |
| `instance_type` | `g5.2xlarge` | GPU instance (1×A10G, 24 GB) |
| `model_src` | `hf://Qwen/Qwen2.5-7B-Instruct` | passed to `fetch_model.sh` |
| `max_model_len` | `8192` | vLLM `--max-model-len` (fits 24 GB) |
| `node_count` | `2` | GPU nodes / tasks |
| `region`, `zone_id`, `subnet_public_ids`, `subnet_private_ids`, `role_arn` | — | set by the test |

## Health checks

vLLM only answers `/health` with 200 once the model has been fetched and loaded,
which takes several minutes on a fresh node. The stack uses vLLM's `/health` for
**both** the container health check (`container_healthcheck_command`, via `python3`
since the image has no `curl`) and the ALB target health check (`healthcheck_path`),
and sets `service_health_check_grace_period_seconds = 1200`.

That grace period is the load-time knob: the ECS service scheduler ignores failing
Elastic Load Balancing, VPC Lattice, and **container** health checks for that window
after a task starts ([`healthCheckGracePeriodSeconds`](https://docs.aws.amazon.com/AmazonECS/latest/APIReference/API_CreateService.html)),
so ECS does not replace the task while the model is still loading. Once loaded,
`/health` returns 200 and both the task and the ALB target become healthy.

## Deviations from the Experiment 2 spec (forced by the module)

- **Root EBS (`root_volume_size = 100`), not instance-store NVMe** — the module
  exposes no instance-store mounting, and storage location is immaterial for an
  untimed serving test.
- **Region follows the test fixtures (default `us-west-2`)** rather than the spec's
  `us-east-1`; `g5.2xlarge` is available there.

## Cost

~$4 per full run (2× g5.2xlarge for ~1.5 h incl. provision/destroy, plus ALB).
Prompt teardown is the main cost control — the test destroys by default; only
`KEEP_AFTER=1` leaves the fleet (and the ECR image) running.
