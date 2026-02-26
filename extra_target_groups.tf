# No stickiness configured: extra target groups are intended for
# protocols like gRPC/OTLP where stickiness is counterproductive.
# ALB distributes individual HTTP/2 streams across targets, and
# pinning clients to one target would defeat load balancing.
resource "aws_lb_target_group" "extra" {
  for_each = var.lb_type == "alb" ? var.extra_target_groups : {}

  name_prefix          = substr("${var.service_name}-", 0, 6)
  port                 = each.value.container_port
  protocol             = each.value.protocol
  target_type          = "instance"
  deregistration_delay = each.value.deregistration_delay
  vpc_id               = data.aws_subnet.load_balancer.vpc_id

  health_check {
    path                = each.value.health_check.path
    port                = each.value.health_check.port
    matcher             = each.value.health_check.matcher
    interval            = each.value.health_check.interval
    timeout             = each.value.health_check.timeout
    healthy_threshold   = 2
    unhealthy_threshold = 10
  }

  tags = merge(local.default_module_tags, {
    Name = "${var.service_name}-${each.key}"
  })
}

resource "aws_lb_listener" "extra" {
  for_each = var.lb_type == "alb" ? var.extra_target_groups : {}

  load_balancer_arn = local.load_balancer_arn
  port              = each.value.listener_port
  protocol          = "HTTPS"
  ssl_policy        = var.ssl_policy
  certificate_arn   = local.acm_certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.extra[each.key].arn
  }

  tags = local.default_module_tags
}

resource "aws_security_group_rule" "extra_listener_ingress" {
  for_each = var.lb_type == "alb" ? var.extra_target_groups : {}

  description       = "Allow HTTPS on port ${each.value.listener_port} for extra target group ${each.key}"
  type              = "ingress"
  from_port         = each.value.listener_port
  to_port           = each.value.listener_port
  protocol          = "tcp"
  cidr_blocks       = var.alb_ingress_cidr_blocks
  security_group_id = tolist(module.pod[0].load_balancer_security_groups)[0]
}
