variable "environment" {
  default = "development"
}
variable "region" {}
variable "role_arn" {
  default = null
}
variable "service_name" {
  default = "test-tempo-grpc"
}
variable "task_role_arn" {
  default = null
}
variable "zone_id" {}


variable "subnet_public_ids" {}
variable "subnet_private_ids" {}
