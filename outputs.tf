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
  value       = module.pod.asg_arn
}

output "asg_name" {
  description = "Autoscaling group name created for the ECS service."
  value       = module.pod.asg_name
}

output "load_balancer_dns_name" {
  description = "Load balancer DNS name."
  value       = module.pod.load_balancer_dns_name
}
