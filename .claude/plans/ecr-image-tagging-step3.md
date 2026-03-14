# Step 3: Add EventBridge + Lambda to ECS Module for ECR Image Tagging

## Context

Part of the ECR Smart Lifecycle Management plan. After an ECS service
reaches steady state (successful deployment), a Lambda tags the deployed
ECR image with `deployed-at-<timestamp>`. This lets ECR lifecycle policies
(in terraform-aws-ecr) retain deployed images as rollback candidates.

The feature is fully opt-in (`enable_ecr_image_tagging = false` default).

## Files to Create

### 1. `assets/ecr_image_tagger/main.py` - Lambda function

Python 3.12 Lambda that:
- Receives EventBridge `SERVICE_STEADY_STATE` event
- Verifies cluster name matches (env var `ECS_CLUSTER_NAME`)
- Calls `ecs:DescribeServices` to get active task definition
- Calls `ecs:DescribeTaskDefinition` to get container image URIs
- For each container image matching ECR pattern
  (`ACCOUNT.dkr.ecr.REGION.amazonaws.com/REPO:TAG`):
  - `ecr:BatchGetImage` to get manifest
  - `ecr:PutImage` with new tag `deployed-at-YYYY-MM-DDTHH-MM-SSZ`
- Skips non-ECR images (Docker Hub, public ECR, etc.)
- Creates regional ECR client for cross-region image support
- Handles `ImageAlreadyExistsException` gracefully

### 2. `ecr_image_tagger.tf` - Terraform resources

All conditional on `var.enable_ecr_image_tagging`:

Uses `infrahouse/lambda-monitored/aws` module (v1.0.4) which provides:
- Lambda function with S3-based packaging
- IAM execution role with CloudWatch Logs permissions
- CloudWatch log group (365d retention)
- SNS topic + alarms (errors, throttles)
- `additional_iam_policy_arns` input for extra permissions

Resources in `ecr_image_tagger.tf`:

| Resource | Purpose |
|----------|---------|
| `module.ecr_image_tagger` | `infrahouse/lambda-monitored/aws` - Lambda + monitoring |
| `aws_cloudwatch_event_rule.ecr_image_tagger` | Match `SERVICE_STEADY_STATE` on this cluster |
| `aws_cloudwatch_event_target.ecr_image_tagger` | Route to Lambda |
| `aws_lambda_permission.ecr_image_tagger` | Allow EventBridge invoke |
| `data.aws_iam_policy_document.ecr_image_tagger` | Business-logic permissions |
| `aws_iam_policy.ecr_image_tagger` | IAM policy from the document above |

The module handles: IAM role creation, assume-role policy,
CloudWatch log group, log permissions, SNS topic, alarms.
We only need to define the business-logic IAM policy and
EventBridge wiring.

**IAM permissions (least privilege) - via `additional_iam_policy_arns`:**
- `ecs:DescribeServices` - scoped to cluster/service
- `ecs:DescribeTaskDefinition` - `*` (not scopeable)
- `ecr:BatchGetImage`, `ecr:DescribeImages` - scoped to
  `ecr:*:ACCOUNT:repository/*`
- `ecr:PutImage` - scoped to `ecr:*:ACCOUNT:repository/*`

**EventBridge pattern:**
```json
{
  "detail-type": ["ECS Service Action"],
  "source": ["aws.ecs"],
  "resources": [CLUSTER_ARN],
  "detail": {
    "eventType": ["INFO"],
    "eventName": ["SERVICE_STEADY_STATE"]
  }
}
```

Scoped to cluster ARN. Since this module creates 1 cluster per service
(cluster name = service_name), this is effectively scoped to our service.
Lambda additionally verifies cluster name as safety check.

**Module invocation sketch:**
```hcl
module "ecr_image_tagger" {
  count   = var.enable_ecr_image_tagging ? 1 : 0
  source  = "registry.infrahouse.com/infrahouse/lambda-monitored/aws"
  version = "1.0.4"

  function_name    = "${var.service_name}-ecr-image-tagger"
  description      = "Tags deployed ECR images for lifecycle retention"
  handler          = "main.lambda_handler"
  lambda_source_dir = "${path.module}/assets/ecr_image_tagger"

  environment_variables = {
    ECS_CLUSTER_NAME       = aws_ecs_cluster.ecs.name
    ECS_SERVICE_NAME       = aws_ecs_service.ecs.name
    DEPLOYED_TAG_PREFIX    = var.deployed_image_tag_prefix
  }

  additional_iam_policy_arns = [
    aws_iam_policy.ecr_image_tagger[0].arn
  ]

  alarm_emails = var.alarm_emails
  tags         = local.default_module_tags
}
```

## Files to Modify

### 3. `variables.tf` - Add two variables

- `enable_ecr_image_tagging` (bool, default `false`)
- `deployed_image_tag_prefix` (string, default `"deployed-at-"`)

### 4. `terraform.tf` - No changes needed

The `lambda-monitored` module declares its own `archive` and `null`
providers internally. The parent module does not need to add them.

## Edge Cases Handled

- **Multi-container tasks**: Tags each ECR image independently
- **Digest-only references** (`@sha256:...`): Resolved via BatchGetImage
- **Cross-account ECR**: Silently fails (no permissions), logs warning
- **Rapid re-deployments**: `ImageAlreadyExistsException` handled gracefully
- **Non-deployment steady state** (autoscaling): Harmless re-tag

## Testing

### End-to-end test: `test_data/httpd_ecr_tagger/` + `tests/test_httpd_ecr_tagger.py`

The test proves the Lambda actually tags ECR images after deployment.

#### Test data config (`test_data/httpd_ecr_tagger/`)

Terraform config that:
- Creates an ECR repository (`aws_ecr_repository`)
- Uses a `null_resource` with `local-exec` to copy the public
  `httpd` image into the ECR repo (crane/skopeo/docker CLI)
- Deploys the ECS module with `docker_image` pointing to the ECR
  image and `enable_ecr_image_tagging = true`
- Outputs: ECR repo name, ECR image URI, service name, cluster name

**Image copy approach — `docker`:**
Docker is available on the self-hosted CI runners.

```hcl
# Simplified sketch
resource "aws_ecr_repository" "test" {
  name         = var.service_name
  force_delete = true
}

resource "null_resource" "push_image" {
  provisioner "local-exec" {
    command = <<-EOT
      aws ecr get-login-password --region ${var.region} \
        | docker login --username AWS --password-stdin \
          ${data.aws_caller_identity.current.account_id
          }.dkr.ecr.${var.region}.amazonaws.com
      docker pull httpd:latest
      docker tag httpd:latest \
        ${aws_ecr_repository.test.repository_url}:latest
      docker push \
        ${aws_ecr_repository.test.repository_url}:latest
    EOT
  }
  depends_on = [aws_ecr_repository.test]
}

module "httpd" {
  source     = "../../"
  # ...same as httpd test config...
  docker_image            = "${aws_ecr_repository.test.repository_url}:latest"
  enable_ecr_image_tagging = true
  depends_on = [null_resource.push_image]
}
```

#### Test file (`tests/test_httpd_ecr_tagger.py`)

Uses `infrahouse-core >= 0.24.0` classes: `ECRRepository`,
`ECRImage`, `ECSService`.

```python
# Simplified sketch
from infrahouse_core.aws import ECRRepository

def test_ecr_image_tagging(
    service_network, keep_after, test_role_arn,
    aws_region, subzone, boto3_session,
    aws_provider_version, cleanup_ecs_task_definitions,
):
    # 1. terraform apply (creates ECR repo, pushes image,
    #    deploys ECS with enable_ecr_image_tagging=true)
    with terraform_apply(...) as output:
        cleanup_ecs_task_definitions(
            output["service_name"]["value"]
        )

        # 2. Wait for service to be healthy (implies steady state)
        for hostname in output["dns_hostnames"]["value"]:
            wait_for_success(f"https://{hostname}")

        # 3. Poll ECR for the deployed-at- tag
        #    (EventBridge -> Lambda is async, may take a minute)
        repo = ECRRepository(
            output["ecr_repo_name"]["value"],
            session=boto3_session,
            region=aws_region,
        )
        image = repo.get_image(tag="latest")

        end_time = time.time() + 300
        deployed_tag = None
        while time.time() < end_time:
            for tag in image.tags:
                if tag.startswith("deployed-at-"):
                    deployed_tag = tag
                    break
            if deployed_tag:
                break
            time.sleep(10)

        assert deployed_tag is not None, (
            "ECR image was not tagged with deployed-at-* "
            "within 5 minutes of steady state"
        )
        LOG.info("ECR image tagged: %s", deployed_tag)
```

### What this validates

- EventBridge rule fires on `SERVICE_STEADY_STATE`
- Lambda receives the event and processes it
- Lambda correctly parses ECR image URI from task definition
- Lambda successfully calls `ecr:BatchGetImage` + `ecr:PutImage`
- The `deployed-at-` tag appears on the image

### Dependencies

- `infrahouse-core ~= 0.24` in `requirements.txt` (for
  `ECRRepository` / `ECRImage` / `ECSService` classes)
- Docker available on the test runner (confirmed)
- Test IAM role needs `ecr:CreateRepository`,
  `ecr:DeleteRepository`, `ecr:GetAuthorizationToken`,
  `ecr:BatchGetImage`, `ecr:PutImage` permissions
  (most of these are already needed for ECS image pulls)

## Verification

1. `terraform fmt -check -recursive` passes
2. `terraform validate` passes
3. `make format && make lint` passes
4. End-to-end test passes: Lambda tags the ECR image