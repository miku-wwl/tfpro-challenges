terraform {
  required_version = "~> 1.6"
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      configuration_aliases = [aws.primary]
      # TODO: Declare aws.dr too.
    }
  }
}

