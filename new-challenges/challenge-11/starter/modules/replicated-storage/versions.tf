terraform {
  required_version = "~> 1.6"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.80"
      # TODO: child 实际使用两个 provider slot，声明完整 configuration_aliases。
      configuration_aliases = [aws.primary]
    }
  }
}

