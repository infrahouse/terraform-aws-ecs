#resource "aws_appautoscaling_target" "ecs_target" {
#  max_capacity       = 2
#  min_capacity       = 1
#  resource_id        = "service/${aws_ecs_cluster.ecs.name}/${aws_ecs_service.ecs.name}"
#  scalable_dimension = "ecs:service:DesiredCount"
#  service_namespace  = "ecs"
#}
#
#resource "aws_appautoscaling_policy" "ecs_policy" {
#  name               = "cpu-auto-scaling"
#  policy_type        = "TargetTrackingScaling"
#  resource_id        = aws_appautoscaling_target.ecs_target.resource_id
#  scalable_dimension = aws_appautoscaling_target.ecs_target.scalable_dimension
#  service_namespace  = aws_appautoscaling_target.ecs_target.service_namespace
#
#  target_tracking_scaling_policy_configuration {
#    predefined_metric_specification {
#      predefined_metric_type = "ECSServiceAverageCPUUtilization"
#    }
#    target_value       = 75
#    scale_in_cooldown  = 300
#    scale_out_cooldown = 300
#  }
#}