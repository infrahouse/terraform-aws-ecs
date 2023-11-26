variable "ssh_key_name" {
  description = "ssh key name installed in ECS host instances."
  type        = string
}

variable "service_name" {
  description = "Service name."
  type        = string
}

variable "docker_image" {
  description = "A container image that will run the service."
  type        = string
}

variable "load_balancer_subnets" {
  description = "Load Balancer Subnets."
  type        = list(string)
}

variable "asg_subnets" {
  description = "Auto Scaling Group Subnets."
  type        = list(string)
}

variable "zone_id" {
  description = "Zone where DNS records will be created for the service and certificate validation."
  type        = string
}

variable "dns_names" {
  description = "List of hostnames the module will create in var.zone_id."
  type        = list(string)
}

variable "internet_gateway_id" {
  description = "Internet gateway id. Usually created by 'infrahouse/service-network/aws'"
  type        = string
}

variable "environment" {
  description = "Name of environment."
  type        = string
  default     = "development"
}

variable "task_role_arn" {
  description = "Task Role ARN. The role will be assumed by a container."
  type        = string
}

variable "alb_healthcheck_path" {
  description = "Application load balancer heath check path."
  type        = string
  default     = "/"
}

variable "container_port" {
  description = "TCP port that a container serves client requests on."
  type        = number
  default     = 8080
}

variable "container_desired_count" {
  description = "Number of containes the ECS service will maintain."
  type        = number
  default     = 2
}