output "dns_hostnames" {
  value = module.httpd.dns_hostnames
}

output "service_name" {
  value = var.service_name
}

output "target_group_arn" {
  value = module.httpd.target_group_arn
}
