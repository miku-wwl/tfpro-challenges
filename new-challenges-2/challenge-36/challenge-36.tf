terraform {
  required_version = ">= 1.6.0, < 2.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.80.0"
    }
  }
}

provider "aws" {
  region                      = "us-east-1"
  access_key                  = "test"
  secret_key                  = "test"
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true

  endpoints {
    sts = "http://localhost:4566"
  }
}

data "aws_caller_identity" "current" {}

resource "terraform_data" "toolchain" {
  input = {
    challenge           = 36
    terraform_required  = ">= 1.6.0, < 2.0.0"
    aws_provider_pinned = "5.80.0"
    account_id          = data.aws_caller_identity.current.account_id
  }
}

output "starter_toolchain" {
  value = terraform_data.toolchain.output
}
