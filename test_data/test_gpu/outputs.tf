output "service_name" {
  value = var.service_name
}

output "task_definition_arn" {
  value = module.httpd.task_definition_arn
}
