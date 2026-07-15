terraform {
  required_version = "~> 1.6"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.100.0"
      # TODO 2: declare both provider slots used by this module.
      configuration_aliases = [aws.primary]
    }
  }
}

