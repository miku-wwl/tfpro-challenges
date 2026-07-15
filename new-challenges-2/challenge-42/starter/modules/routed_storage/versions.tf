terraform {
  required_version = "~> 1.6"
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      version               = "~> 5.100"
      configuration_aliases = [aws.dr, aws.audit]
    }
  }
}
