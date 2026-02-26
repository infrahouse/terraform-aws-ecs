output "dns_hostnames" {
  value = module.tempo.dns_hostnames
}

output "service_name" {
  value = var.service_name
}

output "target_group_arn" {
  value = module.tempo.target_group_arn
}

output "extra_target_group_arns" {
  value = module.tempo.extra_target_group_arns
}
