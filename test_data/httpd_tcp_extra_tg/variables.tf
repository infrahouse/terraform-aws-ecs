variable "region" {}
variable "role_arn" {
  default = null
}
variable "service_name" {
  default = "test-tcp-extra-tg"
}
variable "zone_id" {}

variable "subnet_public_ids" {}
variable "subnet_private_ids" {}

variable "ingress_cidr_blocks" {
  type = list(string)
}
