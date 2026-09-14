# No stickiness configured: extra target groups are intended for
# protocols like gRPC/OTLP where stickiness is counterproductive.
# ALB distributes individual HTTP/2 streams across targets, and
# pinning clients to one target would defeat load balancing.
resource "aws_lb_target_group" "extra" {
  for_each = var.lb_type == "alb" ? var.extra_target_groups : {}

  name_prefix      = substr("${var.service_name}-", 0, 6)
  port             = each.value.container_port
  protocol         = each.value.protocol
  protocol_version = each.value.protocol_version
  target_type      = "instance"
  vpc_id           = data.aws_subnet.load_balancer.vpc_id

  health_check {
    path                = each.value.health_check.path
    port                = "traffic-port"
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
  cidr_blocks       = local.ingress_cidr_blocks
  security_group_id = tolist(module.pod[0].load_balancer_security_groups)[0]
}

resource "aws_lb_target_group" "extra_nlb" {
  for_each = var.lb_type == "nlb" ? var.extra_target_groups : {}

  name_prefix = substr("${var.service_name}-", 0, 6)
  port        = each.value.container_port
  protocol    = "TCP"
  target_type = "instance"
  vpc_id      = data.aws_subnet.load_balancer.vpc_id

  # path and matcher must stay unset: the provider rejects them at plan when the health check protocol is TCP.
  health_check {
    protocol            = "TCP"
    port                = "traffic-port"
    interval            = each.value.health_check.interval
    timeout             = each.value.health_check.timeout
    healthy_threshold   = 2
    unhealthy_threshold = 10
  }

  tags = merge(local.default_module_tags, {
    Name = "${var.service_name}-${each.key}"
  })
}

# Plain TCP: the NLB path has no ACM certificate, so TLS is the application's responsibility.
resource "aws_lb_listener" "extra_nlb" {
  for_each = var.lb_type == "nlb" ? var.extra_target_groups : {}

  load_balancer_arn = local.load_balancer_arn
  port              = each.value.listener_port
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.extra_nlb[each.key].arn
  }

  tags = local.default_module_tags
}

# The tcp-pod backend security group admits all traffic from the NLB security group,
# so the dynamic host ports of bridge-mode tasks need no extra backend rules.
resource "aws_vpc_security_group_ingress_rule" "extra_nlb_listener" {
  for_each = local.extra_nlb_ingress

  description       = "TCP port ${each.value.port} for extra target group ${each.value.name} from ${each.value.cidr}"
  security_group_id = module.tcp-pod[0].load_balancer_security_groups[0]
  from_port         = each.value.port
  to_port           = each.value.port
  ip_protocol       = "tcp"
  cidr_ipv4         = each.value.cidr
  tags              = local.default_module_tags
}

locals {
  # One ingress rule per (extra target group, CIDR) pair.
  extra_nlb_ingress = {
    for pair in setproduct(keys(var.extra_target_groups), local.ingress_cidr_blocks) :
    "${pair[0]}:${pair[1]}" => {
      name = pair[0]
      port = var.extra_target_groups[pair[0]].listener_port
      cidr = pair[1]
    }
    if var.lb_type == "nlb"
  }

  # Read the ARNs through the listeners: ECS rejects a target group that no listener
  # references, so the service must be created or updated after the listener.
  extra_target_group_arns = merge(
    { for k, l in aws_lb_listener.extra : k => l.default_action[0].target_group_arn },
    { for k, l in aws_lb_listener.extra_nlb : k => l.default_action[0].target_group_arn },
  )
}
