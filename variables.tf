variable "alb_access_log_force_destroy" {
  description = "Destroy S3 bucket with access logs even if non-empty"
  type        = bool
  default     = false
}

variable "alb_healthcheck_interval" {
  description = "Number of seconds between checks"
  type        = number
  default     = 5
}

variable "alb_healthcheck_path" {
  description = "Path on the webserver that the elb will check to determine whether the instance is healthy or not."
  type        = string
  default     = "/index.html"
}

variable "alb_idle_timeout" {
  description = "The time in seconds that the connection is allowed to be idle."
  type        = number
  default     = 60
}

variable "alb_healthcheck_response_code_matcher" {
  description = "Range of http return codes that can match"
  type        = string
  default     = "200-299"
}

variable "ami_id" {
  description = "Image for host EC2 instances. If not specified, the latest Amazon image will be used."
  type        = string
  default     = null
}

variable "asg_instance_type" {
  description = "EC2 instances type"
  type        = string
  default     = "t3.micro"
}

variable "asg_health_check_grace_period" {
  description = "ASG will wait up to this number of seconds for instance to become healthy"
  type        = number
  default     = 300
}

variable "asg_min_size" {
  description = "Minimum number of instances in ASG."
  type        = number
  default     = 2
}

variable "asg_max_size" {
  description = "Maximum number of instances in ASG."
  type        = number
  default     = 10
}

variable "asg_subnets" {
  description = "Auto Scaling Group Subnets."
  type        = list(string)
}

variable "assume_dns" {
  description = "If True, create DNS records provided by var.dns_a_records."
  type        = bool
  default     = true
}

variable "autoscaling_metric" {
  description = "Metric to base autoscaling on. Can be ECSServiceAverageCPUUtilization, ECSServiceAverageMemoryUtilization, ALBRequestCountPerTarget"
  type        = string
  default     = "ECSServiceAverageCPUUtilization"
}

variable "autoscaling_target_cpu_usage" {
  description = "If autoscaling_metric is ECSServiceAverageCPUUtilization, how much CPU an ECS service aims to use."
  type        = number
  default     = 80
}

variable "autoscaling_target" {
  description = "Target value for autoscaling_metric."
  type        = number
  default     = null
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
  description = "A list of strings to provide custom configuration for multiple security systems. Supported prefixes are 'label:', 'apparmor:', and 'credentialspec:' or you can specify 'no-new-privileges'"
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
  type = list(object({
    content     = string
    path        = string
    permissions = string
  }))
  default = []
}

variable "internet_gateway_id" {
  description = "Internet gateway id. Usually created by 'infrahouse/service-network/aws'"
  type        = string
}

variable "load_balancer_subnets" {
  description = "Load Balancer Subnets."
  type        = list(string)
}

variable "managed_draining" {
  description = " Enables or disables a graceful shutdown of instances without disturbing workloads."
  type        = bool
  default     = true
}

variable "managed_termination_protection" {
  description = "Enables or disables container-aware termination of instances in the auto scaling group when scale-in happens."
  type        = bool
  default     = true
}

variable "root_volume_size" {
  description = "Root volume size in EC2 instance in Gigabytes"
  type        = number
  default     = 30
}

variable "service_name" {
  description = "Service name."
  type        = string
}

variable "service_health_check_grace_period_seconds" {
  description = "Seconds to ignore failing load balancer health checks on newly instantiated tasks to prevent premature shutdown, up to 2147483647."
  type        = number
  default     = null
}

variable "ssh_key_name" {
  description = "ssh key name installed in ECS host instances."
  type        = string
}

variable "ssh_cidr_block" {
  description = "CIDR range that is allowed to SSH into the backend instances"
  type        = string
  default     = null
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
  description = "The IPC resource namespace to use for the containers in the task. See https://docs.aws.amazon.com/AmazonECS/latest/APIReference/API_TaskDefinition.html"
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

variable "zone_id" {
  description = "Zone where DNS records will be created for the service and certificate validation."
  type        = string
}

variable "enable_cloudwatch_logs" {
  description = "Enable Cloudwatch logs. If enabled, log driver will be awslogs."
  type        = bool
  default     = false
}

variable "cloudwatch_log_group" {
  description = "CloudWatch log group to create and use. Default: /ecs/{name}-{environment}"
  type        = string
  default     = null
}

variable "cloudwatch_log_group_retention" {
  description = "Number of days you want to retain log events in the log group."
  default     = 90
  type        = number
}

variable "enable_cloudwatch_agent" {
  description = "Add cloudwatch agent service to ECS cluster with DAEMON type"
  type        = bool
  default     = false
}

variable "cloudwatch_agent_config_path" {
  description = "Path to cloudwatch agent config on host fs"
  type        = string
  default     = ""
}

variable "cloudwatch_agent_container_resources" {
  description = "Resourcces for cloudwatch agent container"
  type = object({
    cpu    = number
    memory = number
  })
  default = {
    cpu    = 128
    memory = 256
  }
}

variable "cloudwatch_agent_image" {
  description = "Cloudwatch agent image"
  type        = string
  default     = "amazon/cloudwatch-agent:1.300037.1b602"
}

variable "network_mode" {
  description = "The network mode to use for the task. Default is bridge mode."
  type        = string
  default     = "bridge"
}
