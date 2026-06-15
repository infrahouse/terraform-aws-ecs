output "service_name" {
  value = module.vllm.service_name
}
output "cluster_name" {
  value = module.vllm.cluster_name
}
output "dns_hostnames" {
  value = module.vllm.dns_hostnames
}
output "task_definition_arn" {
  value = module.vllm.task_definition_arn
}
