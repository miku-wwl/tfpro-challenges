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
  s3_use_path_style           = true
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true

  # LocalStack endpoints belong to the local half of this scenario.
  # The provider intentionally contains no access_key/secret_key.
  endpoints {
    s3  = "http://localhost:4566"
    sts = "http://localhost:4566"
  }
}

data "aws_caller_identity" "current" {}

resource "aws_s3_bucket" "credential_scenario" {
  bucket        = "tfpro-c58-dynamic-credential-scenario"
  force_destroy = true

  tags = {
    Challenge = "58"
    AuthModel = "local-env-only"
  }
}

output "local_identity_contract" {
  value = {
    account_id = data.aws_caller_identity.current.account_id
    arn        = data.aws_caller_identity.current.arn
    bucket     = aws_s3_bucket.credential_scenario.id
  }
}
