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
  s3_use_path_style           = true

  endpoints {
    s3  = "http://localhost:4566"
    sts = "http://localhost:4566"
  }
}

data "aws_caller_identity" "current" {}

resource "terraform_data" "module_baseline" {
  input = {
    challenge  = 44
    account_id = data.aws_caller_identity.current.account_id
    module     = "not-created-yet"
  }
}

output "starter_module_baseline" {
  value = terraform_data.module_baseline.output
}
