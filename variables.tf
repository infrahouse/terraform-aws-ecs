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

variable "alb_internal" {
  description = "If true, the LB will be internal."
  type        = bool
  default     = false
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

variable "autoscaling_target_cpu_usage" {
  description = "How much CPU an ECS service aims to use."
  type        = number
  default     = 80
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

variable "zone_id" {
  description = "Zone where DNS records will be created for the service and certificate validation."
  type        = string
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
