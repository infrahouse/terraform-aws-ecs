# Getting Started

This guide walks you through deploying your first ECS service using the terraform-aws-ecs module.

## Prerequisites

Before you begin, ensure you have:

1. **Terraform >= 1.5** installed
2. **AWS credentials** configured with permissions for:
    - ECS (clusters, services, task definitions)
    - EC2 (instances, Auto Scaling Groups, security groups)
    - ELB (load balancers, target groups, listeners)
    - IAM (roles, policies)
    - Route53 (DNS records)
    - ACM (certificates)
    - CloudWatch (log groups, alarms)
3. **Existing infrastructure:**
    - VPC with public and private subnets
    - Route53 hosted zone for DNS
    - Internet Gateway attached to VPC

## Cost Estimation

Running an ECS service on EC2 incurs several AWS costs. Here's a rough breakdown for a minimal setup in us-east-1:

| Component | Configuration | Estimated Monthly Cost |
|-----------|---------------|------------------------|
| EC2 instances | 2 × t3.micro | ~$15 |
| Application Load Balancer | Base + LCU | ~$20 + data processing |
| CloudWatch Logs | Ingestion + storage | ~$0.50/GB ingested + $0.03/GB stored |
| Route53 | Hosted zone + queries | ~$0.50 + $0.40/million queries |
| NAT Gateway | If using private subnets | ~$32 + $0.045/GB processed |

**Example scenarios:**

- **Minimal dev setup** (1 t3.micro, ALB, 1GB logs/month): ~$40/month
- **Small production** (2 t3.small, ALB, 10GB logs/month): ~$70/month
- **Medium production** (3 t3.medium, ALB, 50GB logs/month): ~$150/month

**Cost optimization tips:**

- Use spot instances with `on_demand_base_capacity = 1` for non-critical workloads
- Reduce `cloudwatch_log_group_retention` to 7-30 days in development
- Use smaller instance types and let autoscaling add capacity as needed
- Consider NLB instead of ALB if you don't need HTTP-level features (~$6/month cheaper)

> **Note:** These are rough estimates. Actual costs vary by region, data transfer, and usage patterns.
> Use the [AWS Pricing Calculator](https://calculator.aws/) for precise estimates.

## First Deployment

### Step 1: Create the Module Configuration

Create a new Terraform configuration file:

```hcl
# main.tf

terraform {
  required_version = "~> 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.56, < 7.0"
    }
  }
}

provider "aws" {
  region = "us-west-2"
}

# Reference your existing Route53 zone
data "aws_route53_zone" "main" {
  name = "example.com"
}

# Deploy the ECS service
module "my_service" {
  source  = "registry.infrahouse.com/infrahouse/ecs/aws"
  version = "7.5.0"

  providers = {
    aws     = aws
    aws.dns = aws
  }

  # Service configuration
  service_name = "my-web-app"
  environment  = "development"

  # Container configuration
  docker_image   = "nginx:latest"
  container_port = 80

  # Networking - replace with your subnet IDs
  load_balancer_subnets = ["subnet-abc123", "subnet-def456"]
  asg_subnets           = ["subnet-111111", "subnet-222222"]

  # DNS configuration
  zone_id   = data.aws_route53_zone.main.zone_id
  dns_names = ["app"]  # Creates app.example.com

  # Monitoring - required
  alarm_emails = ["devops@example.com"]
}

output "service_url" {
  value = "https://${module.my_service.dns_hostnames[0]}"
}
```

### Step 2: Initialize and Deploy

```bash
# Initialize Terraform
terraform init

# Review the plan
terraform plan

# Apply the configuration
terraform apply
```

### Step 3: Verify the Deployment

After `terraform apply` completes:

1. **Check the outputs** for your service URL (see [all available outputs](https://registry.terraform.io/modules/infrahouse/ecs/aws/latest?tab=outputs))
2. **Confirm SNS subscription** - Check email for subscription confirmation
3. **Access your service** at `https://app.example.com`

## Using Existing VPC Module

If you're using the InfraHouse service-network module:

```hcl
module "vpc" {
  source  = "registry.infrahouse.com/infrahouse/service-network/aws"
  version = "3.5.0"

  service_name       = "my-network"
  vpc_cidr_block     = "10.0.0.0/16"
  availability_zones = ["us-west-2a", "us-west-2b"]
}

module "my_service" {
  source  = "registry.infrahouse.com/infrahouse/ecs/aws"
  version = "7.5.0"

  providers = {
    aws     = aws
    aws.dns = aws
  }

  service_name          = "my-web-app"
  docker_image          = "nginx:latest"
  container_port        = 80
  alarm_emails          = ["devops@example.com"]

  # Use outputs from VPC module
  load_balancer_subnets = module.vpc.subnet_public_ids
  asg_subnets           = module.vpc.subnet_private_ids
  zone_id               = data.aws_route53_zone.main.zone_id
  dns_names             = ["app"]
}
```

## Common Configuration Scenarios

### Production Setup

```hcl
module "production_api" {
  source  = "registry.infrahouse.com/infrahouse/ecs/aws"
  version = "7.5.0"

  providers = {
    aws     = aws
    aws.dns = aws
  }

  service_name = "api"
  environment  = "production"

  # Container
  docker_image   = "my-registry/my-api:v1.2.3"
  container_port = 8080
  container_cpu  = 512
  container_memory = 1024

  # Scaling
  task_desired_count = 3
  task_min_count     = 2
  task_max_count     = 10

  # Instance sizing
  asg_instance_type = "t3.medium"

  # Networking
  load_balancer_subnets = var.public_subnet_ids
  asg_subnets           = var.private_subnet_ids
  zone_id               = var.zone_id
  dns_names             = ["api", ""]  # api.example.com and example.com

  # Monitoring
  alarm_emails                   = ["oncall@example.com", "devops@example.com"]
  cloudwatch_log_group_retention = 365

  tags = {
    team    = "platform"
    project = "api"
  }
}
```

### Cost-Optimized with Spot Instances

```hcl
module "dev_service" {
  source  = "registry.infrahouse.com/infrahouse/ecs/aws"
  version = "7.5.0"

  # ... required parameters ...

  # Use spot instances with 1 on-demand for stability
  on_demand_base_capacity = 1

  # Smaller instances for development
  asg_instance_type = "t3.micro"

  # Limit scaling for cost control
  asg_max_size   = 3
  task_max_count = 5
}
```

## Deploying Updates

There are two ways to deploy new container versions:

### Option 1: Pinned Image Tags (Recommended)

Use specific version tags in your Terraform configuration:

```hcl
docker_image = "123456789012.dkr.ecr.us-west-2.amazonaws.com/my-app:v1.2.3"
```

To deploy a new version, update the tag and run `terraform apply`. In production, this is typically handled by a CI/CD pipeline with approvals, plan reviews, and automated rollback.

This is the recommended approach - it's explicit, auditable, and easy to rollback.

### Option 2: Latest Tag with Force Deploy

If using `latest` or mutable tags:

```hcl
docker_image = "my-app:latest"
```

Force ECS to pull the new image and rotate containers:

```bash
aws ecs update-service \
  --cluster my-cluster \
  --service my-service \
  --force-new-deployment
```

This approach is simpler for development but less traceable in production.

---

## Next Steps

- [Configuration Reference](configuration.md) - All variables explained
- [Troubleshooting](troubleshooting.md) - Common issues and solutions
- [README](https://github.com/infrahouse/terraform-aws-ecs#readme) - Full module documentation