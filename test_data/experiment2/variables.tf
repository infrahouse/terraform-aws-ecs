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
  default = "qwen-7b"
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

# ECR image URI built and pushed by the pytest fixture (vLLM + fetch_model.sh).
variable "docker_image" {
  type = string
}

variable "instance_type" {
  type    = string
  default = "g5.2xlarge" # 1 x A10G (24 GB), 1 GPU
}

# Source ref passed to fetch_model.sh inside the container.
variable "model_src" {
  type    = string
  default = "hf://Qwen/Qwen2.5-7B-Instruct"
}

variable "max_model_len" {
  type    = number
  default = 8192
}

# Number of GPU nodes / tasks (two is the cost floor that still exercises a fleet
# and the load balancer).
variable "node_count" {
  type    = number
  default = 2
}
