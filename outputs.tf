output "service_arn" {
  description = "ECS service ARN."
  value = join(
    ":",
    [
      "arn",
      "aws",
      "ecs",
      data.aws_region.current.name,
      data.aws_caller_identity.current.account_id,
      "service/${aws_ecs_cluster.ecs.name}/${aws_ecs_service.ecs.name}"
    ]
  )
}

output "asg_arn" {
  description = "Autoscaling group ARN created for the ECS service."
  value       = local.arg_arn
}

output "asg_name" {
  description = "Autoscaling group name created for the ECS service."
  value       = local.asg_name
}

output "load_balancer_dns_name" {
  description = "Load balancer DNS name."
  value       = local.load_balancer_dns_name
}

output "dns_hostnames" {
  description = "DNS hostnames where the ECS service is available."
  value = [for h in var.dns_names : trimprefix(join(".", [h, data.aws_route53_zone.this.name]), ".")]
}
