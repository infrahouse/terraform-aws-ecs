resource "aws_appautoscaling_target" "ecs_target" {
  min_capacity       = var.task_min_count
  max_capacity       = var.task_max_count
  resource_id        = "service/${aws_ecs_cluster.ecs.name}/${aws_ecs_service.ecs.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}
locals {
  lb_arn_parts = split("/", local.load_balancer_arn)
  tg_arn_parts = split("/", local.target_group_arn)
}

resource "aws_appautoscaling_policy" "ecs_policy" {
  name               = "auto-scaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ecs_target.resource_id
  scalable_dimension = aws_appautoscaling_target.ecs_target.scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs_target.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = var.autoscaling_metric
      resource_label = var.autoscaling_metric == "ALBRequestCountPerTarget" ? join(
        "/", [
          "app", local.lb_arn_parts[2], local.lb_arn_parts[3],
          "targetgroup", local.tg_arn_parts[1], local.tg_arn_parts[2]
        ]
      ) : null
    }
    target_value = var.autoscaling_metric == "ECSServiceAverageCPUUtilization" ? (
      var.autoscaling_target == null ? var.autoscaling_target_cpu_usage : var.autoscaling_target
    ) : var.autoscaling_target
    scale_in_cooldown  = 300
    scale_out_cooldown = 300
  }
}

# GPU-utilization scaling. A second target-tracking policy on the same ECS service
# target as ecs_policy — the two coexist (Application Auto Scaling scales out to the
# max across policies and scales in only when all agree), so the service scales on
# GPU and CPU together: whichever resource saturates first adds tasks, and a task is
# removed only when both are slack. Gated on gpu_count > 0. The metric comes from the
# host CloudWatch agent's nvidia_gpu collector (configured in datasources.tf), emitted
# into local.gpu_metrics_namespace and aggregated by AutoScalingGroupName.
resource "aws_appautoscaling_policy" "gpu_policy" {
  count              = var.gpu_count > 0 ? 1 : 0
  name               = "auto-scaling-gpu"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ecs_target.resource_id
  scalable_dimension = aws_appautoscaling_target.ecs_target.scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs_target.service_namespace

  target_tracking_scaling_policy_configuration {
    customized_metric_specification {
      metric_name = "nvidia_smi_utilization_gpu"
      namespace   = local.gpu_metrics_namespace
      statistic   = "Average"
      dimensions {
        name  = "AutoScalingGroupName"
        value = local.asg_name
      }
    }
    target_value       = var.gpu_autoscaling_target
    scale_in_cooldown  = 300
    scale_out_cooldown = 300
  }
}
