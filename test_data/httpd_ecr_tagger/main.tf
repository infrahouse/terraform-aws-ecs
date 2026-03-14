data "aws_caller_identity" "this" {}
data "aws_region" "current" {}

resource "aws_ecr_repository" "test" {
  name         = var.service_name
  force_delete = true
}

resource "null_resource" "push_image" {
  provisioner "local-exec" {
    command = <<-EOT
      aws ecr get-login-password --region ${var.region} \
        | docker login --username AWS --password-stdin \
          ${data.aws_caller_identity.this.account_id}.dkr.ecr.${var.region}.amazonaws.com
      docker pull httpd:latest
      docker tag httpd:latest ${aws_ecr_repository.test.repository_url}:latest
      docker push ${aws_ecr_repository.test.repository_url}:latest
    EOT
  }
  depends_on = [aws_ecr_repository.test]
}

# Thread null_resource.push_image.id into the image URI so Terraform
# waits for the push to complete before creating the ECS service,
# without a module-level depends_on (which poisons the plan).
locals {
  ecr_image = "${aws_ecr_repository.test.repository_url}:latest${substr(null_resource.push_image.id, 0, 0)}"
}

module "httpd" {
  source = "../../"
  providers = {
    aws     = aws
    aws.dns = aws
  }
  load_balancer_subnets         = var.subnet_public_ids
  asg_subnets                   = var.subnet_private_ids
  dns_names                     = [""]
  docker_image                  = local.ecr_image
  container_port                = 80
  service_name                  = var.service_name
  zone_id                       = var.zone_id
  container_healthcheck_command = "ls"
  container_command = [
    "sh", "-c",
    "echo '<html><body><h1>It works!</h1></body></html>' > /usr/local/apache2/htdocs/index.html && httpd-foreground"
  ]
  enable_cloudwatch_logs   = true
  enable_ecr_image_tagging = true
  access_log_force_destroy = true
  alarm_emails             = ["test@example.com"]
}
