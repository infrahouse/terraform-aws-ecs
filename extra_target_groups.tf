resource "aws_lb_target_group" "extra" {
  for_each = var.extra_target_groups

  name     = "${var.service_name}-${each.key}"
  port     = each.value.container_port
  protocol = each.value.protocol
  vpc_id   = data.aws_subnet.load_balancer.vpc_id

  health_check {
    path                = each.value.health_check.path
    port                = each.value.health_check.port
    matcher             = each.value.health_check.matcher
    interval            = each.value.health_check.interval
    timeout             = each.value.health_check.timeout
    healthy_threshold   = 2
    unhealthy_threshold = 10
  }

  tags = local.default_module_tags
}

resource "aws_lb_listener" "extra" {
  for_each = var.extra_target_groups

  load_balancer_arn = local.load_balancer_arn
  port              = each.value.listener_port
  protocol          = each.value.protocol

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.extra[each.key].arn
  }

  tags = local.default_module_tags
}
