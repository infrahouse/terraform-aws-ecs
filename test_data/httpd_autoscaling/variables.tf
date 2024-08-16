variable "environment" {
  default = "development"
}
variable "region" {}
variable "role_arn" {}
variable "service_name" {
  default = "test-terraform-aws-ecs"
}
variable "task_role_arn" {}
variable "test_zone" {}
variable "ubuntu_codename" {
  default = "jammy"
}


variable "subnet_public_ids" {}
variable "subnet_private_ids" {}
variable "internet_gateway_id" {}

variable "autoscaling_metric" {}
variable "autoscaling_target" {}
