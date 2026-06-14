output "service_name" {
  value = var.service_name
}

output "cluster_name" {
  value = module.httpd.cluster_name
}

output "dns_hostnames" {
  value = module.httpd.dns_hostnames
}

output "task_definition_arn" {
  value = module.httpd.task_definition_arn
}
