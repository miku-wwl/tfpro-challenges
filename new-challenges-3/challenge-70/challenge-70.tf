terraform {

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
  max_retries                 = 1

  endpoints {
    iam = "http://localhost:4566"
    # Intentional runtime fault: diagnose this endpoint with TF_LOG.
    sts = "http://localhost:4567"
  }
}

data "aws_caller_identity" "runtime" {}

data "aws_iam_policy_document" "trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "diagnostic" {
  name               = "tfpro-challenge-70-diagnostic"
  assume_role_policy = data.aws_iam_policy_document.trust.json

  tags = {
    Challenge = "70"
    Purpose   = "provider-runtime-diagnostics"
  }
}

output "runtime_contract" {
  value = {
    account_id = data.aws_caller_identity.runtime.account_id
    role_name  = aws_iam_role.diagnostic.name
  }
}
