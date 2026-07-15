terraform {
  required_version = "~> 1.6"

  # TODO: 声明 partial backend "s3"，具体值只能由 CLI -backend-config 注入。

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.100"
    }
  }
}

