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

variable "container_port" {
  description = "TCP port that a container serves client requests on."
  type        = number
  default     = 8080
}

variable "container_healthcheck_command" {
  description = "A shell command that a container runs to check if it's healthy. Exit code 0 means healthy, non-zero - unhealthy."
  type        = string
  default     = "curl -f http://localhost/ || exit 1"
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

variable "internet_gateway_id" {
  description = "Internet gateway id. Usually created by 'infrahouse/service-network/aws'"
  type        = string
}

variable "load_balancer_subnets" {
  description = "Load Balancer Subnets."
  type        = list(string)
}

variable "service_name" {
  description = "Service name."
  type        = string
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
  type = list(object({
    name : string
    value : string
  }))
  default = []
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

#variable "task_role_arn" {
#  description = "Task Role ARN. The role will be assumed by a container."
#  type        = string
#}
