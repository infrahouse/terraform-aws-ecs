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
      version = "~> 5.0"
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
  source  = "infrahouse/ecs/aws"
  version = "7.3.0"

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

1. **Check the outputs** for your service URL
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
  source  = "infrahouse/ecs/aws"
  version = "7.3.0"

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
  source  = "infrahouse/ecs/aws"
  version = "7.3.0"

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
  source  = "infrahouse/ecs/aws"
  version = "7.3.0"

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

## Next Steps

- [Configuration Reference](configuration.md) - All variables explained
- [README](https://github.com/infrahouse/terraform-aws-ecs#readme) - Full module documentation