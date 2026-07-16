terraform {
  required_version = "~> 1.6.0"

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

data "aws_iam_policy_document" "permissions" {
  statement {
    sid       = "ReadChallengeArtifacts"
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["arn:aws:s3:::tfpro-challenge-69-artifacts/*"]
  }
}

# The starter is intentionally a working monolith. Apply it before refactoring.
resource "aws_iam_role" "workload" {
  name               = "tfpro-challenge-69-workload"
  assume_role_policy = data.aws_iam_policy_document.trust.json

  tags = {
    Challenge = "69"
    Owner     = "platform"
  }
}

resource "aws_iam_policy" "workload" {
  name   = "tfpro-challenge-69-read-artifacts"
  policy = data.aws_iam_policy_document.permissions.json

  tags = {
    Challenge = "69"
    Owner     = "platform"
  }
}

resource "aws_iam_role_policy_attachment" "workload" {
  role       = aws_iam_role.workload.name
  policy_arn = aws_iam_policy.workload.arn
}

output "identity_contract" {
  value = {
    role_arn   = aws_iam_role.workload.arn
    policy_arn = aws_iam_policy.workload.arn
  }
}
