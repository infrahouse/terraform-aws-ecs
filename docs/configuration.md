# Configuration Reference

This page documents all configuration variables for the terraform-aws-ecs module.

## Required Variables

These variables must be provided - they have no defaults.

### `service_name`

Name of the ECS service. Used for naming resources and CloudWatch log groups.

```hcl
service_name = "my-api"
```

### `docker_image`

Container image to run. Can be from Docker Hub, ECR, or any registry.

```hcl
# Docker Hub
docker_image = "nginx:latest"

# Amazon ECR
docker_image = "123456789012.dkr.ecr.us-west-2.amazonaws.com/my-app:v1.2.3"

# GitHub Container Registry
docker_image = "ghcr.io/myorg/myapp:main"
```

### `alarm_emails`

Email addresses for CloudWatch alarm notifications. At least one required.

```hcl
alarm_emails = ["devops@example.com", "oncall@example.com"]
```

### `load_balancer_subnets`

Subnet IDs for the load balancer. Use public subnets for internet-facing ALBs.

```hcl
load_balancer_subnets = ["subnet-abc123", "subnet-def456"]
```

### `asg_subnets`

Subnet IDs for EC2 instances. Use private subnets for security.

```hcl
asg_subnets = ["subnet-111111", "subnet-222222"]
```

### `dns_names`

Hostnames to create in Route53. Creates DNS records and SSL certificate.

```hcl
# Single hostname: api.example.com
dns_names = ["api"]

# Multiple hostnames with apex domain
dns_names = ["", "www"]  # example.com and www.example.com
```

### `zone_id`

Route53 hosted zone ID for DNS records.

```hcl
zone_id = "Z1234567890ABC"
```

---

## Container Configuration

### `container_port`

TCP port the container listens on.

| Default | Validation |
|---------|------------|
| `8080` | 1-65535 |

```hcl
container_port = 80
```

### `container_cpu`

CPU units for the container. 1 vCPU = 1024 units.

| Default |
|---------|
| `200` |

```hcl
# 0.5 vCPU
container_cpu = 512

# 1 vCPU
container_cpu = 1024
```

### `container_memory`

Hard memory limit in MB. Container is killed if exceeded.

| Default |
|---------|
| `128` |

```hcl
container_memory = 512
```

### `container_memory_reservation`

Soft memory limit in MB. Used for task placement decisions.

| Default |
|---------|
| `null` (uses container_memory) |

```hcl
# Reserve 256MB, allow burst to 512MB
container_memory_reservation = 256
container_memory             = 512
```

### `container_command`

Override the container's default command.

```hcl
container_command = ["python", "app.py", "--port", "8080"]
```

### `container_healthcheck_command`

Container health check command. Exit 0 = healthy.

**Default:** `curl -f http://localhost/ || exit 1`

```hcl
container_healthcheck_command = "wget -q --spider http://localhost:8080/health || exit 1"
```

---

## Auto Scaling Group (ASG) Configuration

### `asg_instance_type`

EC2 instance type for the ASG.

| Default |
|---------|
| `"t3.micro"` |

```hcl
asg_instance_type = "t3.medium"
```

### `asg_min_size`

Minimum number of EC2 instances.

| Default | Validation |
|---------|------------|
| Number of subnets | 1-1000 |

```hcl
asg_min_size = 2
```

### `asg_max_size`

Maximum number of EC2 instances.

| Default | Validation |
|---------|------------|
| Calculated from task requirements | 1-1000 |

**Default Behavior (Recommended):**

When not specified, the module automatically calculates the optimal max size based on:

- Memory capacity needed to run `task_max_count` tasks
- CPU capacity needed to run `task_max_count` tasks
- Minimum of `asg_min_size + 1` for scaling headroom

**When to Override:**

- Cost control: Cap maximum spend
- Capacity planning: Match infrastructure budget
- Testing: Smaller values in non-production

**Warning:** Setting too low can cause:

- ECS tasks failing to place
- Service degradation during traffic spikes
- Deployment failures

```hcl
# Cost control - cap at 10 instances
asg_max_size = 10

# Let module calculate (recommended)
# asg_max_size = null
```

### `asg_health_check_grace_period`

Seconds to wait for instance health check after launch.

| Default |
|---------|
| `300` |

```hcl
asg_health_check_grace_period = 600  # 10 minutes for slow-starting apps
```

### `on_demand_base_capacity`

Minimum on-demand instances when using spot instances.

| Default |
|---------|
| `null` (all on-demand) |

```hcl
# Use spot instances with 1 guaranteed on-demand
on_demand_base_capacity = 1
```

---

## Task Scaling Configuration

### `task_desired_count`

Initial number of tasks to run.

| Default |
|---------|
| `1` |

```hcl
task_desired_count = 3
```

### `task_min_count`

Minimum tasks for autoscaling.

| Default | Validation |
|---------|------------|
| `1` | >= 1 |

```hcl
task_min_count = 2
```

### `task_max_count`

Maximum tasks for autoscaling.

| Default |
|---------|
| `10` |

```hcl
task_max_count = 20
```

### `autoscaling_metric`

Metric for task autoscaling.

| Default | Valid Values |
|---------|--------------|
| `"ECSServiceAverageCPUUtilization"` | `ECSServiceAverageCPUUtilization`, `ECSServiceAverageMemoryUtilization`, `ALBRequestCountPerTarget` |

```hcl
autoscaling_metric = "ECSServiceAverageMemoryUtilization"
```

### `autoscaling_target_cpu_usage`

Target CPU percentage for scaling (when using CPU metric).

| Default | Validation |
|---------|------------|
| `60` | 1-100 |

```hcl
# Scale out at 70% CPU
autoscaling_target_cpu_usage = 70
```

---

## Load Balancer Configuration

### `lb_type`

Load balancer type.

| Default | Valid Values |
|---------|--------------|
| `"alb"` | `alb`, `nlb` |

**When to use ALB (default):**
- HTTP/HTTPS services (REST APIs, web apps)
- Need path-based or host-based routing
- Need HTTP-level health checks (`healthcheck_path`)

**When to use NLB:**
- Raw TCP/UDP services (databases, gRPC, custom protocols)
- Need ultra-low latency or static IPs
- Health check is TCP connection only (no HTTP path)

```hcl
# ALB for HTTP services (default)
lb_type = "alb"

# NLB for TCP services
lb_type = "nlb"
```

> **Note:** With NLB, the `healthcheck_path` variable is ignored. Health checks verify only that a TCP connection can be established on `container_port`.

### `load_balancing_algorithm_type`

ALB target group routing algorithm.

| Default | Valid Values |
|---------|--------------|
| `"round_robin"` | `round_robin`, `least_outstanding_requests` |

```hcl
# Better for varying request times
load_balancing_algorithm_type = "least_outstanding_requests"
```

### `idle_timeout`

Connection idle timeout in seconds.

| Default |
|---------|
| `60` |

```hcl
idle_timeout = 120  # For long-running requests
```

### `healthcheck_path`

HTTP path for ALB health checks.

| Default |
|---------|
| `"/index.html"` |

```hcl
healthcheck_path = "/health"
```

### `healthcheck_interval`

Seconds between health checks.

| Default |
|---------|
| `10` |

### `healthcheck_timeout`

Health check timeout in seconds.

| Default | Validation |
|---------|------------|
| `5` | > 0, must be < healthcheck_interval |

### `healthcheck_response_code_matcher`

HTTP status codes considered healthy.

| Default |
|---------|
| `"200-299"` |

```hcl
healthcheck_response_code_matcher = "200-399"
```

### `extra_target_groups`

Extra target groups for multi-port containers. Each entry creates an ALB
listener and target group, adds a port mapping to the task definition, and
registers the ECS service with the target group.

| Default |
|---------|
| `{}` |

```hcl
extra_target_groups = {
  grpc = {
    listener_port  = 4317
    container_port = 4317
    protocol       = "HTTP"     # optional, default: "HTTP"
    health_check = {            # optional, all fields have defaults
      path     = "/health"      # default: "/"
      port     = "traffic-port" # default: "traffic-port"
      matcher  = "200"          # default: "200-299"
      interval = 30             # default: 30
      timeout  = 5              # default: 5
    }
  }
}
```

> **Note:** Adding or removing entries forces ECS service replacement
> (AWS API limitation on `load_balancer` blocks).

---

## CloudWatch Configuration

### `enable_cloudwatch_logs`

Enable CloudWatch logging for containers.

| Default |
|---------|
| `true` |

```hcl
# Disable logging (not recommended for production)
enable_cloudwatch_logs = false
```

### `cloudwatch_log_group_retention`

Log retention in days.

| Default | Valid Values |
|---------|--------------|
| `365` | 0, 1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653 |

```hcl
cloudwatch_log_group_retention = 30  # 30 days
```

### `cloudwatch_log_kms_key_id`

KMS key ARN for log encryption.

| Default |
|---------|
| `null` (AWS managed encryption) |

```hcl
cloudwatch_log_kms_key_id = "arn:aws:kms:us-west-2:123456789012:key/abc123"
```

### `enable_container_insights`

Enable ECS Container Insights.

| Default |
|---------|
| `false` |

```hcl
enable_container_insights = true
```

---

## Environment and Secrets

### `environment`

Environment name for tagging.

| Default |
|---------|
| `"development"` |

```hcl
environment = "production"
```

### `task_environment_variables`

Environment variables for the container.

```hcl
task_environment_variables = [
  { name = "LOG_LEVEL", value = "info" },
  { name = "API_URL", value = "https://api.example.com" }
]
```

### `task_secrets`

Secrets from AWS Secrets Manager or Parameter Store.

```hcl
task_secrets = [
  {
    name      = "DATABASE_PASSWORD"
    valueFrom = "arn:aws:secretsmanager:us-west-2:123456789012:secret:db-password"
  },
  {
    name      = "API_KEY"
    valueFrom = "arn:aws:ssm:us-west-2:123456789012:parameter/api-key"
  }
]
```

---

## Storage

### `task_efs_volumes`

EFS volumes to mount in containers. Transit encryption is enabled automatically.

```hcl
task_efs_volumes = {
  "data-volume" = {
    file_system_id = "fs-12345678"
    container_path = "/data"
  }
}
```

### `task_local_volumes`

Host volumes to mount in containers.

```hcl
task_local_volumes = {
  "tmp-volume" = {
    host_path      = "/tmp/app"
    container_path = "/app/tmp"
  }
}
```

---

## Advanced Configuration

### `task_role_arn`

IAM role for containers to assume (for AWS API calls).

```hcl
task_role_arn = "arn:aws:iam::123456789012:role/my-task-role"
```

### `execution_extra_policy`

Additional IAM policies for the task execution role.

```hcl
execution_extra_policy = {
  "secrets" = "arn:aws:iam::123456789012:policy/SecretsAccess"
  "ecr"     = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}
```

### `ssh_key_name`

SSH key for EC2 instance access (debugging).

```hcl
ssh_key_name = "my-key-pair"
```

### `ssh_cidr_block`

CIDR allowed for SSH access.

```hcl
ssh_cidr_block = "10.0.0.0/8"
```

### `enable_deployment_circuit_breaker`

Enable ECS deployment circuit breaker.

| Default |
|---------|
| `true` |

### `service_health_check_grace_period_seconds`

Grace period before health checks start for new tasks.

```hcl
# 5 minutes for slow-starting applications
service_health_check_grace_period_seconds = 300
```

---

## Validation Rules

The module includes built-in validation to catch errors early:

| Variable | Validation |
|----------|------------|
| `asg_min_size` | 1-1000 when set |
| `asg_max_size` | 1-1000 when set, must be >= asg_min_size |
| `container_port` | 1-65535 |
| `lb_type` | "alb" or "nlb" |
| `autoscaling_metric` | Valid ECS/ALB metric |
| `autoscaling_target_cpu_usage` | 1-100 |
| `extra_target_groups[*].container_port` | 1-65535 |
| `extra_target_groups[*].listener_port` | 1-65535 |
| `healthcheck_interval` | Must be >= healthcheck_timeout |

---

## Full Example

```hcl
module "production_api" {
  source  = "registry.infrahouse.com/infrahouse/ecs/aws"
  version = "7.3.0"

  providers = {
    aws     = aws
    aws.dns = aws
  }

  # Service
  service_name = "api"
  environment  = "production"

  # Container
  docker_image               = "123456789012.dkr.ecr.us-west-2.amazonaws.com/api:v2.0.0"
  container_port             = 8080
  container_cpu              = 512
  container_memory           = 1024
  container_healthcheck_command = "curl -f http://localhost:8080/health || exit 1"

  # Environment
  task_environment_variables = [
    { name = "LOG_LEVEL", value = "info" }
  ]
  task_secrets = [
    { name = "DB_PASSWORD", valueFrom = "arn:aws:secretsmanager:..." }
  ]

  # Scaling
  task_desired_count         = 3
  task_min_count             = 2
  task_max_count             = 20
  autoscaling_target_cpu_usage = 60

  # Infrastructure
  asg_instance_type     = "t3.medium"
  load_balancer_subnets = var.public_subnet_ids
  asg_subnets           = var.private_subnet_ids

  # Load Balancer
  healthcheck_path     = "/health"
  healthcheck_interval = 15
  healthcheck_timeout  = 10
  idle_timeout         = 120

  # DNS
  zone_id   = var.zone_id
  dns_names = ["api"]

  # Monitoring
  alarm_emails                   = ["oncall@example.com"]
  enable_cloudwatch_logs         = true
  cloudwatch_log_group_retention = 365
  enable_container_insights      = true

  tags = {
    team    = "platform"
    project = "api"
  }
}
```

---

## Outputs

The module exports these outputs for use in downstream configurations.

### Service Outputs

| Output | Description |
|--------|-------------|
| `service_arn` | ECS service ARN |
| `service_name` | ECS service name (for CloudWatch Container Insights metrics) |
| `cluster_name` | ECS cluster name (for CloudWatch Container Insights metrics) |

### DNS and Load Balancer

| Output | Description |
|--------|-------------|
| `dns_hostnames` | List of DNS hostnames where the service is available |
| `load_balancer_arn` | Load balancer ARN |
| `load_balancer_dns_name` | Load balancer DNS name |
| `load_balancer_arn_suffix` | ARN suffix for CloudWatch ALB metrics |
| `target_group_arn` | Primary target group ARN |
| `target_group_arn_suffix` | Target group ARN suffix for CloudWatch metrics |
| `ssl_listener_arn` | SSL listener ARN (ALB only) |
| `acm_certificate_arn` | ACM certificate ARN used by the load balancer (ALB only) |
| `load_balancer_security_groups` | Security groups associated with the load balancer (ALB only) |

### Auto Scaling Group

| Output | Description |
|--------|-------------|
| `asg_arn` | Auto Scaling Group ARN |
| `asg_name` | Auto Scaling Group name |

### IAM and Security

| Output | Description |
|--------|-------------|
| `task_execution_role_arn` | Task execution role ARN (used by ECS agent) |
| `task_execution_role_name` | Task execution role name |
| `backend_security_group` | Security group ID of backend instances |

### CloudWatch

| Output | Description |
|--------|-------------|
| `cloudwatch_log_group_name` | Main CloudWatch log group name for ECS tasks |
| `cloudwatch_log_group_names` | Map of all log group names: `ecs`, `syslog`, `dmesg` |

### Usage Examples

**Reference DNS hostnames:**

```hcl
output "service_urls" {
  value = [for h in module.ecs.dns_hostnames : "https://${h}"]
}
```

**Create CloudWatch dashboard:**

```hcl
resource "aws_cloudwatch_dashboard" "ecs" {
  dashboard_name = "ecs-${module.ecs.service_name}"
  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        properties = {
          metrics = [
            ["AWS/ECS", "CPUUtilization", "ClusterName", module.ecs.cluster_name, "ServiceName", module.ecs.service_name]
          ]
        }
      }
    ]
  })
}
```

**Access log groups:**

```hcl
# Main ECS task logs
locals {
  ecs_log_group = module.ecs.cloudwatch_log_group_name
}

# All log groups (v7.0+ returns a map)
locals {
  ecs_logs    = module.ecs.cloudwatch_log_group_names["ecs"]
  syslog_logs = module.ecs.cloudwatch_log_group_names["syslog"]
  dmesg_logs  = module.ecs.cloudwatch_log_group_names["dmesg"]
}
```