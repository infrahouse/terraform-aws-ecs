output "zone_id" {
  value = data.aws_route53_zone.cicd.zone_id
}

output "jumphost_hostname" {
  value = random_pet.hostname.id
}

output "load_balancer_dns_name" {
  value = module.httpd.load_balancer_dns_name
}

output "service_name" {
  value = var.service_name
}

output "dns_hostnames" {
  value = module.httpd.dns_hostnames
}
