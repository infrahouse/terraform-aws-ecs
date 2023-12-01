output "service_arn" {
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