variable "access_log_force_destroy" {
  description = "Destroy S3 bucket with access logs even if non-empty"
  type        = bool
  default     = false
}

variable "alarm_emails" {
  description = <<-EOT
    List of email addresses to receive CloudWatch alarm notifications.
    Required for monitoring ECS service health and performance issues.

    Example: ["devops@example.com", "oncall@example.com"]
  EOT
  type        = list(string)

  validation {
    condition     = length(var.alarm_emails) > 0
    error_message = "At least one email address must be provided for alarm notifications."
  }

  validation {
    condition = alltrue([
      for email in var.alarm_emails : can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", email))
    ])
    error_message = "All alarm_emails must be valid email addresses."
  }
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

  validation {
    condition     = var.asg_min_size == null ? true : var.asg_min_size >= 1 && var.asg_min_size <= 1000
    error_message = "asg_min_size must be between 1 and 1000 when specified."
  }
}

variable "asg_max_size" {
  description = <<-EOT
    Maximum number of instances in ASG.

    **Default Behavior (Recommended):**
    When not specified, the module automatically calculates the optimal max size based on:
    - Memory capacity: instances needed to run task_max_count tasks based on container_memory
      (or container_memory_reservation if set)
    - CPU capacity: instances needed to run task_max_count tasks based on container_cpu
    - Minimum headroom: at least asg_min_size + 1 to allow scaling

    The calculation accounts for:
    - Instance type memory/CPU (from var.asg_instance_type)
    - Reserved resources for system overhead (~1GB memory)
    - Daemon overhead: CloudWatch agent (128 CPU, 256MB) and, if enabled,
      Vector Agent (128 CPU, 256MB)

    **When to Override:**
    - Cost control: Limit maximum spend by capping instance count
    - Capacity planning: Match a specific infrastructure budget
    - Testing: Use smaller values in non-production environments

    **When NOT to Override:**
    - If you're unsure - the automatic calculation is designed for optimal scaling
    - Without understanding your workload's resource requirements

    **Warning:**
    Setting this too low can cause:
    - ECS tasks failing to place (no capacity available)
    - Service degradation during traffic spikes
    - Deployment failures if new tasks can't be scheduled

    Must be >= asg_min_size when both are explicitly set.

    Example: asg_max_size = 10  # Cap at 10 instances for cost control
  EOT
  type        = number
  default     = null

  validation {
    condition     = var.asg_max_size == null ? true : var.asg_max_size >= 1 && var.asg_max_size <= 1000
    error_message = "asg_max_size must be between 1 and 1000 when specified."
  }
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

  validation {
    condition     = var.autoscaling_target_cpu_usage >= 1 && var.autoscaling_target_cpu_usage <= 100
    error_message = "autoscaling_target_cpu_usage must be a percentage between 1 and 100."
  }
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

    Version Selection:
    - Current version (1.300062.0b1304) was the latest stable release at time of pinning
    - Verified to work with Amazon Linux 2023 and ECS
    - No known security vulnerabilities at time of selection

    Updating the Version:
    1. Check available versions: https://gallery.ecr.aws/cloudwatch-agent/cloudwatch-agent
    2. Review AWS CloudWatch Agent release notes for breaking changes
    3. Test in non-production environment first
    4. Override this variable with the new version:
       cloudwatch_agent_image = "public.ecr.aws/cloudwatch-agent/cloudwatch-agent:NEW_VERSION"

    Security Monitoring:
    - Monitor AWS security bulletins: https://aws.amazon.com/security/security-bulletins/
    - Subscribe to CloudWatch Agent GitHub releases: https://github.com/aws/amazon-cloudwatch-agent
    - Consider automated container vulnerability scanning (e.g., AWS ECR scanning, Trivy)
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

variable "enable_vector_agent" {
  description = <<-EOT
    Deploy a Vector Agent daemon on every EC2 instance in this cluster.
    Collects container logs and host metrics, forwards to a Vector Aggregator.

    Requires: vector_aggregator_endpoint must be set when using the default config.
  EOT
  type        = bool
  default     = false
}

variable "vector_agent_image" {
  description = "Vector Agent container image."
  type        = string
  default     = "timberio/vector:0.43.1-alpine"
}

variable "vector_aggregator_endpoint" {
  description = <<-EOT
    Vector Aggregator address (host:port) for the agent to forward data to.
    Used by the default config template. Ignored if vector_agent_config is set.

    Example: "vector-aggregator.sandbox.tinyfish.io:6000"
  EOT
  type        = string
  default     = null
}

variable "vector_agent_config" {
  description = <<-EOT
    Custom Vector Agent config (YAML string). When provided, replaces
    the built-in default config template entirely.

    Example:
      vector_agent_config = templatefile("files/vector.yaml.tftpl", { ... })
  EOT
  type        = string
  default     = null
}

variable "vector_agent_task_policy_arns" {
  description = <<-EOT
    List of IAM policy ARNs to attach to the Vector Agent task role.
    The default config (Docker logs + host metrics forwarded to an
    aggregator) needs no AWS permissions. Add policies here if your
    Vector config uses AWS sinks (S3, CloudWatch, Kinesis, etc.).

    Example:
      vector_agent_task_policy_arns = [
        "arn:aws:iam::aws:policy/CloudWatchLogsFullAccess"
      ]
  EOT
  type        = list(string)
  default     = []
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

  validation {
    condition     = var.healthcheck_timeout > 0
    error_message = "healthcheck_timeout must be greater than 0."
  }
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
  description = <<-EOT
    A shell command that a container runs to check if it's healthy.
    Exit code 0 means healthy, non-zero - unhealthy.
    Set to null to omit the healthCheck block entirely
    (useful for distroless images that have no shell).
  EOT
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

variable "container_memory_reservation" {
  description = <<-EOT
    Soft memory limit in megabytes for the container. The container can use more memory
    if available on the host, up to the hard limit (container_memory).
    If null, no reservation is set and container_memory acts as both reservation and limit.
    Must be greater than 0 and less than or equal to container_memory when specified.
  EOT
  type        = number
  default     = null

  validation {
    condition     = var.container_memory_reservation == null ? true : var.container_memory_reservation > 0
    error_message = "container_memory_reservation must be greater than 0 when specified."
  }
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

variable "ssl_policy" {
  description = <<-EOT
    TLS security policy for HTTPS listeners.
    Used by extra target group listeners. Will be passed to
    website-pod when it supports it
    (see infrahouse/terraform-aws-website-pod#114).

    See https://docs.aws.amazon.com/elasticloadbalancing/latest/application/describe-ssl-policies.html
    or run `aws elbv2 describe-ssl-policies` to list all available policies.

    Common choices:
      - ELBSecurityPolicy-TLS13-1-2-Res-2021-06  (restrictive, default)
      - ELBSecurityPolicy-TLS13-1-2-Ext1-2021-06 (wider compatibility)
  EOT
  type        = string
  default     = "ELBSecurityPolicy-TLS13-1-2-Res-2021-06"

  validation {
    condition     = can(regex("^ELBSecurityPolicy-", var.ssl_policy))
    error_message = <<-EOT
      ssl_policy must be a valid AWS ELB security policy name
      (starts with "ELBSecurityPolicy-").
      Got: ${var.ssl_policy}
      Run `aws elbv2 describe-ssl-policies` to list available policies.
    EOT
  }
}

variable "alb_ingress_cidr_blocks" {
  description = <<-EOT
    List of CIDR blocks allowed to access the ALB.
    Applied to both the primary listener (via website-pod)
    and any extra target group listeners.
  EOT
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "load_balancing_algorithm_type" {
  description = <<-EOF
    Load balancing algorithm for the target group.

    **Available algorithms:**
    - `round_robin` (default): Distributes requests evenly across healthy targets.
      Best for: General-purpose workloads with similar request processing times.

    - `least_outstanding_requests`: Routes to the target with fewest in-flight requests.
      Best for: Workloads with varying request processing times, long-running requests,
      or when backend instances have different capacities.

    **Note:** When stickiness is enabled, the algorithm applies only to initial
    session assignment. Subsequent requests from the same client go to the same target.
  EOF
  type        = string
  default     = "round_robin"

  validation {
    condition     = contains(["round_robin", "least_outstanding_requests"], var.load_balancing_algorithm_type)
    error_message = "load_balancing_algorithm_type must be either 'round_robin' or 'least_outstanding_requests'."
  }
}

variable "target_group_protocol" {
  description = <<-EOF
    Protocol for the ALB target group.

    **Available protocols:**
    - `HTTP` (default): Standard backend communication. ALB terminates SSL and
      forwards unencrypted traffic to containers.
      Best for: Most applications where SSL termination at the load balancer is sufficient.

    - `HTTPS`: End-to-end encryption. ALB forwards encrypted traffic to containers.
      The container must have a valid TLS certificate and listen on HTTPS.
      Best for: Compliance requirements (e.g., PCI-DSS), zero-trust architectures,
      or when data must remain encrypted in transit within the VPC.

    **Note:** When using HTTPS, ensure your container:
    - Has a valid TLS certificate (self-signed is acceptable for internal traffic)
    - Listens on the container_port using HTTPS
    - The health check path is accessible over HTTPS
  EOF
  type        = string
  default     = "HTTP"

  validation {
    condition     = contains(["HTTP", "HTTPS"], var.target_group_protocol)
    error_message = "target_group_protocol must be either 'HTTP' or 'HTTPS'."
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
  description = "Tags to apply to resources created by the module."
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

  validation {
    condition     = var.task_min_count >= 1
    error_message = "task_min_count must be at least 1."
  }
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

variable "extra_target_groups" {
  type = map(object({
    listener_port    = number
    container_port   = number
    protocol         = optional(string, "HTTP")
    protocol_version = optional(string, null)
    health_check = optional(object({
      path     = optional(string, "/")
      matcher  = optional(string, "200-299")
      interval = optional(number, 30)
      timeout  = optional(number, 5)
    }), {})
  }))
  default     = {}
  description = <<-EOT
    Extra target groups to register with the ECS service.
    Each entry creates a target group, an ALB listener on
    listener_port, a port mapping in the task definition, and
    a load_balancer block on the ECS service.

    Use a map keyed by a descriptive name. This is more stable
    than a list because reordering does not force service
    replacement.

    NOTE: adding or removing entries forces ECS service
    replacement (AWS API limitation on load_balancer blocks).

    protocol_version controls the protocol version for the
    target group. Valid values: "HTTP1" (default when null),
    "HTTP2", or "GRPC". When set to "GRPC", the health check
    matcher should use gRPC status codes (e.g., "0" for OK,
    "12" for UNIMPLEMENTED, or "0-99" for any).

    Example:
      extra_target_groups = {
        otlp_grpc = {
          listener_port    = 4317
          container_port   = 4317
          protocol         = "HTTP"
          protocol_version = "GRPC"
          health_check = {
            path    = "/"
            matcher = "0-99"
          }
        }
      }
  EOT

  validation {
    condition = alltrue([
      for k, v in var.extra_target_groups :
      v.container_port >= 1 && v.container_port <= 65535
    ])
    error_message = <<-EOT
      All container_port values in extra_target_groups must be
      between 1 and 65535.
    EOT
  }

  validation {
    condition = alltrue([
      for k, v in var.extra_target_groups :
      v.listener_port >= 1 && v.listener_port <= 65535
    ])
    error_message = <<-EOT
      All listener_port values in extra_target_groups must be
      between 1 and 65535.
    EOT
  }

  validation {
    condition = alltrue([
      for k, v in var.extra_target_groups :
      v.protocol_version == null ? true : contains(
        ["HTTP1", "HTTP2", "GRPC"], v.protocol_version
      )
    ])
    error_message = <<-EOT
      protocol_version must be one of "HTTP1", "HTTP2", "GRPC",
      or null (defaults to HTTP1).
    EOT
  }
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

variable "dns_routing_policy" {
  description = <<-EOF
    DNS routing policy for Route53 A records.

    **Available policies:**
    - `simple` (default): Standard DNS routing. Each A record resolves directly to the ALB.
      Best for: Single deployments, standard configurations.

    - `weighted`: Enables Route53 weighted routing policy for zero-downtime migrations.
      Requires: dns_set_identifier must be set.
      Best for: Blue/green deployments, gradual traffic migration, A/B testing.

    **Migration workflow example:**
    1. Deploy new service with `dns_routing_policy = "weighted"`, `dns_weight = 0`
    2. Convert existing service to weighted with `dns_weight = 100`
    3. Gradually shift: 90/10 -> 50/50 -> 10/90 -> 0/100
    4. Remove old service

    **Note:** When using weighted routing, you can have multiple modules create
    records for the same DNS name, each with a unique dns_set_identifier.
  EOF
  type        = string
  default     = "simple"

  validation {
    condition     = contains(["simple", "weighted"], var.dns_routing_policy)
    error_message = "dns_routing_policy must be either 'simple' or 'weighted'. Got: ${var.dns_routing_policy}"
  }
}

variable "dns_weight" {
  description = <<-EOF
    Weight for Route53 weighted routing policy (0-255).
    Only used when dns_routing_policy = "weighted".

    **Weight behavior:**
    - 0: No traffic routed to this endpoint (useful during initial deployment)
    - 255: Maximum weight priority
    - Traffic distribution = (this_weight / sum_of_all_weights) * 100%

    **Examples:**
    - Two endpoints with weights 100 and 100: 50% each
    - Two endpoints with weights 100 and 0: 100% to first, 0% to second
    - Three endpoints with weights 70, 20, 10: 70%, 20%, 10%

    **Migration tip:** Start new deployments with weight=0, then gradually increase.
  EOF
  type        = number
  default     = 100

  validation {
    condition     = var.dns_weight >= 0 && var.dns_weight <= 255
    error_message = "dns_weight must be between 0 and 255. Got: ${var.dns_weight}"
  }
}

variable "dns_set_identifier" {
  description = <<-EOF
    Unique identifier for weighted routing records.
    Required when dns_routing_policy is not "simple".

    This identifier distinguishes between multiple weighted records with the same name.
    Must be unique across all weighted records for the same DNS name.

    **Recommended naming conventions:**
    - Environment-based: "production-blue", "production-green"
    - Version-based: "v1", "v2", "v3"
    - Region-based: "us-west-2-primary", "us-east-1-secondary"
    - Module-based: "website-pod-main", "ecs-service-new"

    **Example:**
    ```hcl
    # Old service (being deprecated)
    dns_routing_policy = "weighted"
    dns_set_identifier = "legacy-service"
    dns_weight         = 10

    # New service (receiving traffic)
    dns_routing_policy = "weighted"
    dns_set_identifier = "new-service"
    dns_weight         = 90
    ```
  EOF
  type        = string
  default     = null

  validation {
    condition     = var.dns_set_identifier == null ? true : length(var.dns_set_identifier) <= 128
    error_message = "dns_set_identifier must be 128 characters or less."
  }
}
