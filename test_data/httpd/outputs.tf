output "zone_id" {
  value = var.zone_id
}

output "jumphost_hostname" {
  value = random_pet.hostname.id
}

output "dns_hostnames" {
  value = module.httpd.dns_hostnames
}

output "service_name" {
  value = var.service_name
}

output "cloudwatch_log_group_names" {
  value = module.httpd.cloudwatch_log_group_names
}
