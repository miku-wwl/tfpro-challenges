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
    iam = "http://localhost:4566"
    sts = "http://localhost:4566"
  }
}

data "aws_caller_identity" "source" {}

data "aws_iam_policy_document" "trust" {
  statement {
    actions = ["sts:AssumeRole"]
    effect  = "Allow"

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.source.account_id}:root"]
    }
  }
}

resource "aws_iam_role" "deployment" {
  name               = "tfpro-c48-deployment"
  assume_role_policy = data.aws_iam_policy_document.trust.json

  tags = {
    Challenge = "48"
    Purpose   = "authentication-chain"
  }
}

output "source_identity" {
  value = {
    account_id = data.aws_caller_identity.source.account_id
    arn        = data.aws_caller_identity.source.arn
    role_arn   = aws_iam_role.deployment.arn
  }
}

# Tasks remove static credentials, introduce a temporary shared profile,
# add an assume-role alias, and verify the delegated session.
