variable "access_log_force_destroy" {
  description = "Destroy S3 bucket with access logs even if non-empty"
  type        = bool
  default     = false
}

variable "ami_id" {
  description = <<-EOT
    Image for host EC2 instances.
    If not specified, the latest Amazon Linux 2023 ECS-optimized image will be used.
  EOT
  type        = string
  default     = null
}

variable "asg_instance_type" {
  description = "EC2 instances type"
  type        = string
  default     = "t3.micro"
}

variable "asg_health_check_grace_period" {
  description = <<-EOT
    ASG will wait up to this number of seconds for instance to become healthy.
    Default: 300 seconds (5 minutes)
  EOT
  type        = number
  default     = 300
}

variable "asg_min_size" {
  description = <<-EOT
    Minimum number of instances in ASG.
    Default: The number of subnets (one instance per subnet for high availability).
  EOT
  type        = number
  default     = null
}

variable "asg_max_size" {
  description = <<-EOT
    Maximum number of instances in ASG.
    Default: Automatically calculated based on number of tasks and their memory requirements.
  EOT
  type        = number
  default     = null
}

variable "asg_subnets" {
  description = "Auto Scaling Group Subnets."
  type        = list(string)
}

variable "assume_dns" {
  description = <<-EOT
    If true, create DNS records provided by var.dns_names.
    Set to false if DNS records are managed externally.
  EOT
  type        = bool
  default     = true
}

variable "autoscaling_metric" {
  description = <<-EOT
    Metric to base autoscaling on.

    Valid values:
    - "ECSServiceAverageCPUUtilization" (default) - Scale based on CPU usage
    - "ECSServiceAverageMemoryUtilization" - Scale based on memory usage
    - "ALBRequestCountPerTarget" - Scale based on ALB requests per target
  EOT
  type        = string
  default     = "ECSServiceAverageCPUUtilization"

  validation {
    condition = contains([
      "ECSServiceAverageCPUUtilization",
      "ECSServiceAverageMemoryUtilization",
      "ALBRequestCountPerTarget"
    ], var.autoscaling_metric)
    error_message = "autoscaling_metric must be one of: ECSServiceAverageCPUUtilization, ECSServiceAverageMemoryUtilization, or ALBRequestCountPerTarget."
  }
}

variable "autoscaling_target_cpu_usage" {
  description = <<-EOT
    Target CPU utilization percentage for autoscaling.
    Only used when autoscaling_metric is "ECSServiceAverageCPUUtilization".

    ECS will scale in/out to maintain this CPU usage level.
    Default: 60% (matches website-pod default for consistency)
  EOT
  type        = number
  default     = 60
}

variable "autoscaling_target" {
  description = "Target value for autoscaling_metric."
  type        = number
  default     = null
}

variable "cloudwatch_agent_image" {
  description = <<-EOT
    CloudWatch agent container image.

    Default is pinned to a specific version for stability and reproducibility.
    Pinned versions prevent unexpected breaking changes when AWS updates the agent.

    You can override this to use ":latest" if you want automatic updates,
    though this is not recommended for production environments.

    Check available versions: https://gallery.ecr.aws/cloudwatch-agent/cloudwatch-agent
  EOT
  type        = string
  default     = "public.ecr.aws/cloudwatch-agent/cloudwatch-agent:1.300062.0b1304"
}

variable "cloudwatch_log_group" {
  description = <<-EOT
    CloudWatch log group name to create and use.
    Default: /ecs/{var.environment}/{var.service_name}

    Example: If environment="production" and service_name="api",
    the log group will be "/ecs/production/api"
  EOT
  type        = string
  default     = null
}

variable "cloudwatch_log_group_retention" {
  description = "Number of days you want to retain log events in the log group."
  default     = 365
  type        = number

  validation {
    condition = contains([
      0, 1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653
    ], var.cloudwatch_log_group_retention)
    error_message = "cloudwatch_log_group_retention must be one of the valid CloudWatch retention periods: 0 (never expire), 1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, or 3653 days."
  }
}

variable "enable_cloudwatch_logs" {
  description = <<-EOT
    Enable CloudWatch Logs for ECS tasks.
    If enabled, containers will use "awslogs" log driver.

    Default: true (recommended for production environments)
  EOT
  type        = bool
  default     = true
}

variable "cloudwatch_log_kms_key_id" {
  description = <<-EOT
    KMS key ID (ARN) to encrypt CloudWatch logs.

    If not specified, logs will use AWS managed encryption.
    For enhanced security and compliance, provide a customer-managed KMS key.

    Example: "arn:aws:kms:us-east-1:123456789012:key/12345678-1234-1234-1234-123456789012"
  EOT
  type        = string
  default     = null
}

variable "enable_container_insights" {
  description = "Enable container insights feature on ECS cluster."
  type        = bool
  default     = false
}

variable "execution_extra_policy" {
  description = <<-EOT
    A map of extra policies attached to the task execution role.
    The task execution role is used by the ECS agent to pull images, write logs, and access secrets.

    Key: Arbitrary identifier (e.g., "secrets_access")
    Value: IAM policy ARN

    Example:
      execution_extra_policy = {
        "secrets_access" = "arn:aws:iam::123456789012:policy/ECSSecretsAccess"
        "ecr_pull"       = "arn:aws:iam::123456789012:policy/ECRPullPolicy"
      }
  EOT
  type        = map(string)
  default     = {}
}

variable "healthcheck_interval" {
  description = "Number of seconds between checks"
  type        = number
  default     = 10
}

variable "healthcheck_timeout" {
  description = "Healthcheck timeout"
  type        = number
  default     = 5
}

variable "healthcheck_path" {
  description = "Path on the webserver that the elb will check to determine whether the instance is healthy or not."
  type        = string
  default     = "/index.html"
}

variable "idle_timeout" {
  description = "The time in seconds that the connection is allowed to be idle."
  type        = number
  default     = 60
}

variable "healthcheck_response_code_matcher" {
  description = "Range of http return codes that can match"
  type        = string
  default     = "200-299"
}

variable "container_command" {
  description = "If specified, use this list of strings as a docker command."
  type        = list(string)
  default     = null
}

variable "container_healthcheck_command" {
  description = "A shell command that a container runs to check if it's healthy. Exit code 0 means healthy, non-zero - unhealthy."
  type        = string
  default     = "curl -f http://localhost/ || exit 1"
}

variable "container_cpu" {
  description = "Number of CPU units that a container is going to use."
  type        = number
  default     = 200
}

variable "container_memory" {
  description = "Amount of RAM in megabytes the container is going to use."
  type        = number
  default     = 128
}

variable "container_port" {
  description = "TCP port that a container serves client requests on."
  type        = number
  default     = 8080

  validation {
    condition     = var.container_port >= 1 && var.container_port <= 65535
    error_message = "container_port must be between 1 and 65535."
  }
}

variable "dns_names" {
  description = "List of hostnames the module will create in var.zone_id."
  type        = list(string)
}

variable "docker_image" {
  description = "A container image that will run the service."
  type        = string
}

variable "dockerSecurityOptions" {
  description = <<-EOT
    A list of strings to provide custom configuration for multiple security systems.

    Supported options:
    - "no-new-privileges" - Prevent privilege escalation
    - "label:<value>" - SELinux labels
    - "apparmor:<value>" - AppArmor profile
    - "credentialspec:<value>" - Credential specifications (Windows)

    Example:
      dockerSecurityOptions = [
        "no-new-privileges",
        "label:type:container_runtime_t"
      ]
  EOT
  type        = list(string)
  default     = null
}

variable "environment" {
  description = "Name of environment."
  type        = string
  default     = "development"
}

variable "extra_files" {
  description = "Additional files to create on a host EC2 instance."
  type = list(
    object(
      {
        content     = string
        path        = string
        permissions = string
      }
    )
  )
  default = []
}

variable "lb_type" {
  description = "Load balancer type. ALB or NLB"
  type        = string
  default     = "alb"

  validation {
    condition     = contains(["alb", "nlb"], lower(var.lb_type))
    error_message = "lb_type must be either 'alb' or 'nlb' (case-insensitive)."
  }
}

variable "load_balancer_subnets" {
  description = "Load Balancer Subnets."
  type        = list(string)
}

variable "managed_draining" {
  description = "Enables or disables a graceful shutdown of instances without disturbing workloads."
  type        = bool
  default     = true
}

variable "managed_termination_protection" {
  description = "Enables or disables container-aware termination of instances in the auto scaling group when scale-in happens."
  type        = bool
  default     = true
}

variable "on_demand_base_capacity" {
  description = "If specified, the ASG will request spot instances and this will be the minimal number of on-demand instances."
  type        = number
  default     = null
}

variable "root_volume_size" {
  description = "Root volume size in EC2 instance in Gigabytes"
  type        = number
  default     = 30
}

variable "service_name" {
  description = "Service name"
  type        = string
}

variable "service_health_check_grace_period_seconds" {
  description = <<-EOT
    Seconds to ignore failing load balancer health checks on newly instantiated tasks.
    This prevents ECS from killing tasks that are still starting up.

    Use this when:
    - Your application takes time to initialize (e.g., loading data, warming caches)
    - Health checks fail during the startup period
    - You see tasks being killed and restarted repeatedly

    Default: null (uses ECS default behavior)
    Range: 0 to 2147483647 seconds

    Example: 300 (5 minutes grace period for slow-starting applications)
  EOT
  type        = number
  default     = null
}

variable "ssh_key_name" {
  description = "ssh key name installed in ECS host instances."
  type        = string
  default     = null
}

variable "ssh_cidr_block" {
  description = "CIDR range that is allowed to SSH into the backend instances"
  type        = string
  default     = null
}

variable "tags" {
  description = "Tags to apply to resources creatded by the module."
  type        = map(string)
  default     = {}
}

variable "task_secrets" {
  description = "Secrets to pass to a container. A `name` will be the environment variable. valueFrom is a secret ARN."
  type = list(
    object(
      {
        name : string
        valueFrom : string
      }
    )
  )
  default = []
}

variable "task_desired_count" {
  description = "Number of containers the ECS service will maintain."
  type        = number
  default     = 1
}

variable "task_environment_variables" {
  description = "Environment variables passed down to a task."
  type = list(
    object(
      {
        name : string
        value : string
      }
    )
  )
  default = []
}

variable "task_ipc_mode" {
  description = <<-EOT
    The IPC resource namespace to use for the containers in the task.
    Controls how containers share inter-process communication resources.

    Valid values:
    - null (default) - Each container has its own private IPC namespace
    - "host" - Containers use the host's IPC namespace (use with caution)
    - "task" - All containers in the task share the same IPC namespace
    - "none" - IPC namespace is disabled

    Use "task" when:
    - Containers need to communicate via shared memory
    - Running multi-container applications that use IPC (e.g., sidecars with shared memory)

    Reference: https://docs.aws.amazon.com/AmazonECS/latest/APIReference/API_TaskDefinition.html
  EOT
  type        = string
  default     = null
}

variable "task_max_count" {
  description = "Highest number of tasks to run"
  type        = number
  default     = 10
}

variable "task_min_count" {
  description = "Lowest number of tasks to run"
  type        = number
  default     = 1
}

variable "task_role_arn" {
  description = "Task Role ARN. The role will be assumed by a container."
  type        = string
  default     = null
}

variable "task_efs_volumes" {
  description = "Map name->{file_system_id, container_path} of EFS volumes defined in task and available for containers to mount."
  type = map(
    object(
      {
        file_system_id : string
        container_path : string
      }
    )
  )
  default = {}
}

variable "task_local_volumes" {
  description = "Map name->{host_path, container_path} of local volumes defined in task and available for containers to mount."
  type = map(
    object(
      {
        host_path : string
        container_path : string
      }
    )
  )
  default = {}
}

variable "upstream_module" {
  description = "Module that called this module."
  type        = string
  default     = null
}

variable "users" {
  description = "A list of maps with user definitions according to the cloud-init format"
  default     = null
  type        = any
  # Check https://cloudinit.readthedocs.io/en/latest/reference/examples.html#including-users-and-groups
  # for fields description and examples.
  #   type = list(
  #     object(
  #       {
  #         name : string
  #         expiredate : optional(string)
  #         gecos : optional(string)
  #         homedir : optional(string)
  #         primary_group : optional(string)
  #         groups : optional(string) # Comma separated list of strings e.g. groups: users, admin
  #         selinux_user : optional(string)
  #         lock_passwd : optional(bool)
  #         inactive : optional(number)
  #         passwd : optional(string)
  #         no_create_home : optional(bool)
  #         no_user_group : optional(bool)
  #         no_log_init : optional(bool)
  #         ssh_import_id : optional(list(string))
  #         ssh_authorized_keys : optional(list(string))
  #         sudo : any # Can be either false or a list of strings e.g. sudo = ["ALL=(ALL) NOPASSWD:ALL"]
  #         system : optional(bool)
  #         snapuser : optional(string)
  #       }
  #     )
  #   )
}

variable "vanta_owner" {
  description = <<-EOT
    The email address of the instance's owner for Vanta tracking.

    Must be set to the email address of an existing user in Vanta.
    If the email doesn't match a Vanta user, no owner will be assigned.
  EOT
  type        = string
  default     = null
}

variable "vanta_production_environments" {
  description = "Environment names to consider production grade in Vanta."
  type        = list(string)
  default = [
    "production",
    "prod"
  ]
}

variable "vanta_description" {
  description = "This tag allows administrators to set a description, for instance, or add any other descriptive information."
  type        = string
  default     = null
}

variable "vanta_contains_user_data" {
  description = <<-EOT
    This tag allows administrators to define whether or not a resource contains user data.

    Set to true if the resource contains user data, false otherwise.
    Used for Vanta compliance tracking.
  EOT
  type        = bool
  default     = false
}

variable "vanta_contains_ephi" {
  description = <<-EOT
    This tag allows administrators to define whether or not a resource contains
    electronically Protected Health Information (ePHI).

    Set to true if the resource contains ePHI, false otherwise.
    Used for HIPAA compliance tracking in Vanta.
  EOT
  type        = bool
  default     = false
}

variable "vanta_user_data_stored" {
  description = "This tag allows administrators to describe the type of user data the instance contains."
  type        = string
  default     = null
}

variable "vanta_no_alert" {
  description = <<-EOT
    Mark a resource as out of scope for Vanta audit.

    If set, you must provide a reason explaining why the resource
    is not relevant to the audit.
  EOT
  type        = string
  default     = null
}

variable "zone_id" {
  description = "Zone where DNS records will be created for the service and certificate validation."
  type        = string
}

variable "execution_task_role_policy_arn" {
  description = "Extra policy for execution task role."
  type        = string
  default     = null
}

variable "enable_deployment_circuit_breaker" {
  description = "Enable ECS deployment circuit breaker."
  type        = bool
  default     = true
}

variable "sns_topic_arn" {
  description = "SNS topic arn for sending alerts on failed deployments."
  type        = string
  default     = null
}

variable "cloudinit_extra_commands" {
  description = "Extra commands for run on ASG."
  type        = list(string)
  default     = []
}

variable "extra_instance_profile_permissions" {
  description = "A JSON with a permissions policy document. The policy will be attached to the ASG instance profile."
  type        = string
  default     = null
}

variable "certificate_issuers" {
  description = <<-EOT
    List of certificate authority domains allowed to issue certificates for this domain (e.g., ["amazon.com", "letsencrypt.org"]).
    The module will format these as CAA records.
  EOT
  type        = list(string)
  default     = ["amazon.com"]
}
