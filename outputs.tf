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

output "load_balancer_arn" {
  description = "Load balancer ARN."
  value       = local.load_balancer_arn
}

output "load_balancer_dns_name" {
  description = "Load balancer DNS name."
  value       = local.load_balancer_dns_name
}

output "dns_hostnames" {
  description = "DNS hostnames where the ECS service is available."
  value       = [for h in var.dns_names : trimprefix(join(".", [h, data.aws_route53_zone.this.name]), ".")]
}

output "task_execution_role_name" {
  description = "Task execution role is a role that ECS agent gets."
  value       = aws_iam_role.ecs_task_execution_role.name
}

output "task_execution_role_arn" {
  description = "Task execution role is a role that ECS agent gets."
  value       = aws_iam_role.ecs_task_execution_role.arn
}

output "backend_security_group" {
  description = "Security group of backend."
  value       = local.backend_security_group
}

output "ssl_listener_arn" {
  description = "SSL listener ARN"
  value       = var.lb_type == "alb" ? module.pod[0].ssl_listener_arn : null
}

output "load_balancer_security_groups" {
  description = "Security groups associated with the load balancer"
  value       = var.lb_type == "alb" ? module.pod[0].load_balancer_security_groups : null
}

output "acm_certificate_arn" {
  description = "ARN of the ACM certificate used by the load balancer"
  value       = var.lb_type == "alb" ? module.pod[0].acm_certificate_arn : null
}
