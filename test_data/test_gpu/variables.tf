variable "environment" {
  type    = string
  default = "development"
}
variable "region" {
  type = string
}
variable "role_arn" {
  type    = string
  default = null
}
variable "service_name" {
  type    = string
  default = "test-terraform-aws-ecs-gpu"
}
variable "zone_id" {
  type = string
}

variable "subnet_public_ids" {
  type = list(string)
}
variable "subnet_private_ids" {
  type = list(string)
}

variable "gpu_count" {
  type    = number
  default = 0
}
