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
variable "test_zone" {}
variable "ubuntu_codename" {
  default = "jammy"
}


variable "subnet_public_ids" {}
variable "subnet_private_ids" {}
variable "internet_gateway_id" {}
