output "zone_id" {
  value = data.aws_route53_zone.cicd.zone_id
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
