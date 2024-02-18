module "jumphost" {
  source  = "infrahouse/jumphost/aws"
  version = "~> 1.5"
  # insert the 4 required variables here
  environment      = var.environment
  keypair_name     = aws_key_pair.test.key_name
  route53_zone_id  = data.aws_route53_zone.cicd.zone_id
  subnet_ids       = module.service-network.subnet_public_ids
  route53_hostname = "jumphost-ecs"
}
