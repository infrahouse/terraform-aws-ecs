# GPU observability dashboard. Puts the GPU-vs-CPU bottleneck signals side by side so
# an operator can judge instance-type efficiency: autoscaling keeps the service
# available, but a persistent "GPU idle / CPU busy" signature means the fleet is
# buying GPUs for CPU headroom and a CPU-richer instance type may be cheaper.
# Gated on gpu_count > 0, so non-GPU consumers get nothing new.
locals {
  gpu_dashboard_widgets = concat(
    [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6
        properties = {
          title  = "GPU utilization (%)"
          region = data.aws_region.current.name
          view   = "timeSeries"
          stat   = "Average"
          period = 60
          metrics = [
            ["${local.gpu_metrics_namespace}", "nvidia_smi_utilization_gpu", "AutoScalingGroupName", local.asg_name]
          ]
          yAxis = { left = { min = 0, max = 100 } }
          annotations = {
            horizontal = [{ label = "target", value = var.gpu_autoscaling_target }]
          }
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6
        properties = {
          title  = "Service CPU utilization (%)"
          region = data.aws_region.current.name
          view   = "timeSeries"
          stat   = "Average"
          period = 60
          metrics = [
            ["AWS/ECS", "CPUUtilization", "ClusterName", aws_ecs_cluster.ecs.name, "ServiceName", aws_ecs_service.ecs.name]
          ]
          yAxis = { left = { min = 0, max = 100 } }
          annotations = {
            horizontal = [{ label = "target", value = var.autoscaling_target_cpu_usage }]
          }
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 12
        height = 6
        properties = {
          title  = "GPU memory (MB)"
          region = data.aws_region.current.name
          view   = "timeSeries"
          stat   = "Average"
          period = 60
          metrics = [
            ["${local.gpu_metrics_namespace}", "nvidia_smi_memory_used", "AutoScalingGroupName", local.asg_name],
            ["${local.gpu_metrics_namespace}", "nvidia_smi_memory_total", "AutoScalingGroupName", local.asg_name]
          ]
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 6
        width  = 12
        height = 6
        properties = {
          title  = "ASG instance count"
          region = data.aws_region.current.name
          view   = "timeSeries"
          stat   = "Average"
          period = 60
          metrics = [
            ["AWS/AutoScaling", "GroupInServiceInstances", "AutoScalingGroupName", local.asg_name]
          ]
        }
      }
    ],
    # RunningTaskCount is only published when Container Insights is enabled.
    var.enable_container_insights ? [
      {
        type   = "metric"
        x      = 0
        y      = 12
        width  = 12
        height = 6
        properties = {
          title  = "Running task count"
          region = data.aws_region.current.name
          view   = "timeSeries"
          stat   = "Average"
          period = 60
          metrics = [
            ["ECS/ContainerInsights", "RunningTaskCount", "ClusterName", aws_ecs_cluster.ecs.name, "ServiceName", aws_ecs_service.ecs.name]
          ]
        }
      }
    ] : []
  )
}

resource "aws_cloudwatch_dashboard" "gpu" {
  count          = var.gpu_count > 0 ? 1 : 0
  dashboard_name = "${var.service_name}-gpu"
  dashboard_body = jsonencode({ widgets = local.gpu_dashboard_widgets })
}
