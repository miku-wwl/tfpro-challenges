terraform {
  required_version = "~> 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.80.0"
    }
  }
}

# This provider intentionally obtains its source credentials from the
# environment. Readme Task 1 sets LocalStack-only values before any plan.
provider "aws" {
  region                      = "us-east-1"
  s3_use_path_style           = true
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true

  endpoints {
    iam = "http://localhost:4566"
    s3  = "http://localhost:4566"
    sts = "http://localhost:4566"
  }
}

locals {
  role_name   = "TfProChallenge80Deployer"
  role_arn    = "arn:aws:iam::000000000000:role/TfProChallenge80Deployer"
  bucket_name = "tfpro-challenge80-delegated"
}

data "aws_caller_identity" "bootstrap" {}

data "aws_iam_policy_document" "trust" {
  statement {
    sid     = "AllowLocalStackAccount"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::000000000000:root"]
    }
  }
}

data "aws_iam_policy_document" "delegated_s3" {
  statement {
    sid = "ManageChallengeBucket"
    actions = [
      "s3:CreateBucket",
      "s3:DeleteBucket",
      "s3:GetBucketLocation",
      "s3:ListBucket",
    ]
    resources = [
      "arn:aws:s3:::${local.bucket_name}",
      "arn:aws:s3:::${local.bucket_name}/*",
    ]
  }
}

resource "aws_iam_role" "deployer" {
  name               = local.role_name
  assume_role_policy = data.aws_iam_policy_document.trust.json

  tags = {
    Challenge = "80"
  }
}

resource "aws_iam_policy" "delegated_s3" {
  name   = "TfProChallenge80DelegatedS3"
  policy = data.aws_iam_policy_document.delegated_s3.json
}

resource "aws_iam_role_policy_attachment" "deployer" {
  role       = aws_iam_role.deployer.name
  policy_arn = aws_iam_policy.delegated_s3.arn
}

output "bootstrap_identity" {
  value = {
    account_id = data.aws_caller_identity.bootstrap.account_id
    arn        = data.aws_caller_identity.bootstrap.arn
  }
}

# Tasks 3-5 add the delegated provider, identity data sources, bucket, and
# identity contract only after the role exists in LocalStack.
