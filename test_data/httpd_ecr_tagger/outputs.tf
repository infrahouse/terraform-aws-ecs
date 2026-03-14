output "dns_hostnames" {
  value = module.httpd.dns_hostnames
}

output "service_name" {
  value = var.service_name
}

output "cluster_name" {
  value = module.httpd.cluster_name
}

output "ecr_repo_name" {
  value = aws_ecr_repository.test.name
}

output "ecr_repo_url" {
  value = aws_ecr_repository.test.repository_url
}
