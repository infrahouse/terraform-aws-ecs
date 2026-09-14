output "service_name" {
  value = var.service_name
}

output "load_balancer_arn" {
  value = module.httpd.load_balancer_arn
}

output "load_balancer_dns_name" {
  value = module.httpd.load_balancer_dns_name
}

output "load_balancer_security_groups" {
  value = module.httpd.load_balancer_security_groups
}

output "target_group_arn" {
  value = module.httpd.target_group_arn
}

output "extra_target_group_arns" {
  value = module.httpd.extra_target_group_arns
}
