output "service_name" {
  value = var.service_name
}

output "cluster_name" {
  value = module.httpd.cluster_name
}

output "asg_name" {
  value = module.httpd.asg_name
}

output "dns_hostnames" {
  value = module.httpd.dns_hostnames
}
