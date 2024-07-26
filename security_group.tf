resource "aws_security_group" "backend_extra" {
  description = "Backend extrac security group for service ${var.service_name}"
  name_prefix = "${var.service_name}-"
  vpc_id      = data.aws_subnet.selected.vpc_id

  tags = merge(
    {
      Name : "ECS ${var.service_name} backend"
    },
    local.tags
  )
}

resource "aws_vpc_security_group_ingress_rule" "backend_extra_reserved" {
  description       = "ECS reserved ports for service ${var.service_name}"
  security_group_id = aws_security_group.backend_extra.id
  from_port         = 2375
  to_port           = 2376
  ip_protocol       = "tcp"
  cidr_ipv4         = "0.0.0.0/0"
  tags = merge(
    {
      Name = "ECS reserved"
    },
    local.tags
  )
}

resource "aws_vpc_security_group_ingress_rule" "backend_extra_user" {
  description       = "ECS user traffic ports for service ${var.service_name}"
  security_group_id = aws_security_group.backend_extra.id
  from_port         = 32768
  to_port           = 65535
  ip_protocol       = "tcp"
  cidr_ipv4         = "0.0.0.0/0"
  tags = merge(
    {
      Name = "ECS user traffic"
    },
    local.tags
  )
}
