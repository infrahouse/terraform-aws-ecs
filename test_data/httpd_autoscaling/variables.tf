variable "environment" {
  default = "development"
}
variable "region" {}
variable "role_arn" {
  default = null
}

variable "service_name" {
  default = "test-terraform-aws-ecs"
}
variable "task_role_arn" {
  default = null
}
variable "zone_id" {}
variable "ubuntu_codename" {
  default = "jammy"
}


variable "subnet_public_ids" {}
variable "subnet_private_ids" {}

variable "autoscaling_metric" {}
variable "autoscaling_target" {}
