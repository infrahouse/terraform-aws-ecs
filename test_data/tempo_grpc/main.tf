locals {
  tempo_config = <<-YAML
    server:
      http_listen_port: 3200

    distributor:
      receivers:
        otlp:
          protocols:
            grpc:
              endpoint: "0.0.0.0:4317"

    storage:
      trace:
        backend: local
        local:
          path: /tmp/tempo/blocks
        wal:
          path: /tmp/tempo/wal
  YAML
}

module "tempo" {
  source = "../../"
  providers = {
    aws     = aws
    aws.dns = aws
  }
  load_balancer_subnets = var.subnet_public_ids
  asg_subnets           = var.subnet_private_ids
  dns_names             = [""]
  docker_image          = "grafana/tempo:2.7.1"
  container_port        = 3200
  container_cpu         = 256
  container_memory      = 512
  service_name          = var.service_name
  zone_id               = var.zone_id

  container_healthcheck_command = "wget -qO- http://localhost:3200/ready || exit 1"
  container_command             = ["-config.file=/etc/tempo/tempo.yaml"]

  task_role_arn            = aws_iam_role.task_role.arn
  enable_cloudwatch_logs   = true
  access_log_force_destroy = true
  alarm_emails             = ["test@example.com"]

  extra_files = [
    {
      content     = local.tempo_config
      path        = "/etc/tempo/tempo.yaml"
      permissions = "0644"
    }
  ]
  task_local_volumes = {
    "tempo-config" = {
      host_path      = "/etc/tempo"
      container_path = "/etc/tempo"
    }
  }

  extra_target_groups = {
    otlp_grpc = {
      listener_port    = 4317
      container_port   = 4317
      protocol         = "HTTP"
      protocol_version = "GRPC"
      health_check = {
        path    = "/"
        matcher = "0-99"
      }
    }
  }

  service_health_check_grace_period_seconds = 120
}
