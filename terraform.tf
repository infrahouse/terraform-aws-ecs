terraform {
  required_version = "~> 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.11"
      configuration_aliases = [
        aws.dns # AWS provider for DNS
      ]
    }
  }
}
