terraform {
  required_version = "~> 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.56"
      configuration_aliases = [
        aws.dns # AWS provider for DNS
      ]
    }
    cloudinit = {

      source  = "hashicorp/cloudinit"
      version = "~> 2.3"
    }
  }
}
