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
