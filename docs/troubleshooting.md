# Troubleshooting

This page covers common issues and their solutions when using the terraform-aws-ecs module.

## Tasks Stuck in PENDING

**Symptom:** ECS tasks remain in PENDING state and never start running.

**Common Causes:**

1. **Insufficient ASG capacity** - Not enough EC2 instances to host the tasks
2. **Memory constraints** - Container memory exceeds available instance memory
3. **CPU constraints** - Container CPU exceeds available instance CPU

**Diagnosis:**

```bash
# Check ECS service events
aws ecs describe-services \
  --cluster my-cluster \
  --services my-service \
  --query 'services[0].events[:5]'

# Check container instance resources
aws ecs describe-container-instances \
  --cluster my-cluster \
  --container-instances $(aws ecs list-container-instances --cluster my-cluster --query 'containerInstanceArns' --output text) \
  --query 'containerInstances[*].{id:ec2InstanceId,cpu:remainingResources[?name==`CPU`].integerValue,memory:remainingResources[?name==`MEMORY`].integerValue}'
```

**Solutions:**

- Increase `asg_max_size` to allow more instances
- Reduce `container_memory` or `container_cpu` requirements
- Use a larger `asg_instance_type`
- Check if `task_max_count` exceeds what `asg_max_size` can support

```hcl
# Ensure ASG can host all tasks
# Rule of thumb: each t3.micro can run ~1-2 small containers
asg_instance_type = "t3.small"  # Upgrade from t3.micro
asg_max_size      = 5           # Allow more instances
```

---

## Health Checks Failing

**Symptom:** Tasks start but get terminated, service keeps restarting tasks.

**Common Causes:**

1. **Mismatched health check paths** - ALB checks different path than container serves
2. **Container health check vs ALB health check confusion**
3. **Application not ready in time**

**Understanding the Two Health Checks:**

| Health Check | Purpose | Configuration |
|--------------|---------|---------------|
| Container health check | ECS agent checks container is healthy | `container_healthcheck_command` |
| ALB health check | Load balancer checks application responds | `healthcheck_path` |

**Diagnosis:**

```bash
# Check target group health
aws elbv2 describe-target-health \
  --target-group-arn <target-group-arn>

# Check ECS task stopped reason
aws ecs describe-tasks \
  --cluster my-cluster \
  --tasks <task-arn> \
  --query 'tasks[0].stoppedReason'
```

**Solutions:**

```hcl
# Ensure both health checks are aligned
container_healthcheck_command = "curl -f http://localhost:8080/health || exit 1"
healthcheck_path              = "/health"
container_port                = 8080

# Increase grace period for slow-starting apps
service_health_check_grace_period_seconds = 300
asg_health_check_grace_period             = 600
```

---

## Certificate Validation Stuck

**Symptom:** `terraform apply` hangs at ACM certificate creation, waiting for validation.

**Common Causes:**

1. **Wrong zone_id** - Certificate validation DNS records created in wrong zone
2. **DNS propagation delay** - Records exist but haven't propagated
3. **Zone not publicly accessible** - Private hosted zone can't be validated

**Diagnosis:**

```bash
# Check certificate status
aws acm describe-certificate \
  --certificate-arn <cert-arn> \
  --query 'Certificate.DomainValidationOptions'

# Verify DNS records exist
dig _abc123.example.com CNAME
```

**Solutions:**

1. **Verify zone_id matches your domain:**

```hcl
# Get the correct zone ID
data "aws_route53_zone" "main" {
  name         = "example.com"
  private_zone = false  # Must be public for ACM validation
}

module "ecs" {
  # ...
  zone_id = data.aws_route53_zone.main.zone_id
}
```

2. **Check DNS propagation:**

```bash
# Wait and retry - propagation can take 5-30 minutes
# Or check with multiple DNS servers
dig @8.8.8.8 _abc123.example.com CNAME
dig @1.1.1.1 _abc123.example.com CNAME
```

3. **For cross-account DNS:** Use the `aws.dns` provider alias:

```hcl
provider "aws" {
  alias  = "dns"
  region = "us-east-1"
  # Different credentials for DNS account
}

module "ecs" {
  providers = {
    aws     = aws
    aws.dns = aws.dns  # Route53 in different account
  }
  # ...
}
```

---

## "Invalid for_each argument" Error

**Symptom:** Terraform fails with a cryptic error about `for_each`:

```
Error: Invalid for_each argument

on .../ssl.tf line 25, in resource "aws_route53_record" "cert_validation":
   25:   for_each = {...}

The "for_each" set includes values derived from resource attributes that
cannot be determined until apply, and so Terraform cannot determine the
full set of keys that will identify the instances of this resource.
```

**Cause:** You're creating a Route53 zone and the ECS module in the same Terraform plan. The module needs the zone_id to create DNS records, but Terraform can't resolve the dependency graph because the zone doesn't exist yet.

**Why This Happens:**

The module uses `for_each` to create certificate validation records. When the zone_id comes from a resource being created in the same plan, Terraform can't determine how many records to create until the zone exists.

**Solution:** Split into two applies or use `depends_on`:

**Option 1: Two-stage apply (recommended)**

```hcl
# Stage 1: Create the zone first
resource "aws_route53_zone" "main" {
  name = "example.com"
}

# Apply stage 1:
# terraform apply -target=aws_route53_zone.main
```

```hcl
# Stage 2: Then use the zone with the module
module "ecs" {
  source = "registry.infrahouse.com/infrahouse/ecs/aws"
  # ...
  zone_id = aws_route53_zone.main.zone_id
}

# Apply stage 2:
# terraform apply
```

**Option 2: Import existing zone**

If the zone already exists in AWS but not in your state:

```bash
# Import the existing zone
terraform import aws_route53_zone.main Z1234567890ABC
```

**Option 3: Use data source for existing zone**

If the zone was created separately:

```hcl
# Reference existing zone instead of creating it
data "aws_route53_zone" "main" {
  name = "example.com"
}

module "ecs" {
  # ...
  zone_id = data.aws_route53_zone.main.zone_id
}
```

---

## Container Can't Pull Image

**Symptom:** Tasks fail with "CannotPullContainerError".

**Common Causes:**

1. **ECR authentication** - Missing permissions to pull from ECR
2. **Network access** - No route to container registry
3. **Image doesn't exist** - Wrong tag or repository name

**Solutions:**

```hcl
# For ECR images, ensure execution role has permissions
# The module handles this automatically, but verify the image exists:
docker_image = "123456789012.dkr.ecr.us-west-2.amazonaws.com/my-app:v1.0.0"

# For private registries, use task_secrets for credentials
task_secrets = [
  {
    name      = "DOCKER_AUTH"
    valueFrom = "arn:aws:secretsmanager:us-west-2:123456789012:secret:docker-creds"
  }
]
```

For private subnets, ensure NAT Gateway or VPC endpoints exist for:
- ECR API (`com.amazonaws.region.ecr.api`)
- ECR Docker (`com.amazonaws.region.ecr.dkr`)
- S3 (`com.amazonaws.region.s3`) - for ECR image layers
- CloudWatch Logs (`com.amazonaws.region.logs`)

---

## Service Not Accessible

**Symptom:** Service deploys successfully but can't be reached via DNS.

**Checklist:**

1. **DNS propagation** - Wait 1-5 minutes for DNS records
2. **Security groups** - ALB must allow inbound 443/80
3. **Target group health** - At least one healthy target
4. **Certificate status** - Must be "Issued"

**Diagnosis:**

```bash
# Check DNS resolution
dig api.example.com

# Check ALB security group allows traffic
aws ec2 describe-security-groups --group-ids <alb-sg-id>

# Check certificate status
aws acm describe-certificate --certificate-arn <cert-arn> \
  --query 'Certificate.Status'
```

---

## Debugging on EC2 Instances

One of the key benefits of running ECS on EC2 (as opposed to Fargate) is the ability to SSH into instances and debug containers directly - including dead ones. This is impossible with Fargate.

### Connecting to an Instance

**Option 1: SSM Session Manager (recommended)**

The easiest method - no SSH keys or open ports required:

1. Go to **EC2 Console** > **Instances**
2. Select your ECS instance
3. Click **Connect** > **Session Manager** > **Connect**

This opens a browser-based terminal directly on the instance.

**Option 2: SSH**

Configure SSH access in the module:

```hcl
ssh_key_name   = "my-key-pair"
ssh_cidr_block = "10.0.0.0/8"  # Your VPN/bastion CIDR
```

Then connect via SSH from your network.

### Docker Commands

**List all containers (including exited):**

```bash
docker ps -a
```

This shows container IDs, status, and exit codes - crucial for finding crashed containers.

**Inspect container details:**

```bash
docker inspect <container-id>
```

This reveals health check output, environment variables, mount points, and exit reasons - very useful for debugging health check failures.

**View container logs:**

```bash
# View logs (not available in AWS Console for individual containers!)
docker logs <container-id>

# Follow logs in real-time
docker logs -f <container-id>

# Last 100 lines
docker logs --tail 100 <container-id>
```

**Connect to a running container:**

```bash
docker exec -it <container-id> /bin/sh
# or if bash is available:
docker exec -it <container-id> /bin/bash
```

This lets you inspect the filesystem, check running processes, test network connectivity from inside the container.

**Monitor container resource usage:**

```bash
docker stats
```

Shows live CPU, memory, network, and disk I/O for all containers.

### ECS Agent Logs

Check agent-level errors:

```bash
cat /var/log/ecs/ecs-agent.log

# Follow in real-time
tail -f /var/log/ecs/ecs-agent.log

# Search for errors
grep -i error /var/log/ecs/ecs-agent.log
```

Common issues found here:
- Image pull failures
- Task placement errors
- Container runtime problems

### System-Level Debugging

Standard Linux tools work on ECS instances:

```bash
# CPU usage per core
mpstat -P ALL 1

# Memory and swap
vmstat 1

# Disk I/O
iostat -x 1

# Network traffic capture
sudo tcpdump -i any port 8080

# Process list
ps aux | grep docker

# Disk space
df -h
```

---

## Frequently Asked Questions

### Can I use Fargate instead of EC2?

No. This module is intentionally EC2-only by design.

If you need Fargate, this module is not for you. The module targets users who need:

- **Direct host access** for performance tuning and troubleshooting
- **Container inspection** via `docker` commands on instances
- **System-level observability** (mpstat, vmstat, iostat, tcpdump)
- **Lower cost** than Fargate for sustained workloads

EC2-backed ECS provides all of this at a lower price point than Fargate. Using Fargate would defeat the purpose.

### How do I access logs?

**Application logs (container stdout/stderr):**

CloudWatch Logs at these log groups:
- `/ecs/{environment}/{service_name}` - Main container logs
- `/ecs/{environment}/{service_name}/syslog` - EC2 system logs
- `/ecs/{environment}/{service_name}/dmesg` - EC2 kernel logs

Access via AWS Console or CLI:

```bash
aws logs tail /ecs/production/my-service --follow
```

**ALB access logs:**

ALB access logs are managed by the underlying `website-pod` module and stored in S3.

### How do I SSH to instances?

Configure SSH access in the module:

```hcl
ssh_key_name   = "my-key-pair"
ssh_cidr_block = "10.0.0.0/8"  # Your bastion/VPN CIDR
```

You can also add SSH users via module inputs. See `extra_user_data` for custom cloud-init configuration.

For most cases, **SSM Session Manager** is easier - no SSH keys or open ports required. See [Debugging on EC2 Instances](#debugging-on-ec2-instances) above.

---

## Getting Help

If you're still stuck:

1. **Check ECS service events** for specific error messages
2. **Review CloudWatch logs** at `/ecs/{environment}/{service_name}`
3. **Open an issue** at [GitHub](https://github.com/infrahouse/terraform-aws-ecs/issues) with:
    - Terraform version
    - Module version
    - Relevant configuration (sanitized)
    - Error messages