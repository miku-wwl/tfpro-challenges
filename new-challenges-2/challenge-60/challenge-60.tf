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
  s3_use_path_style           = true
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true

  endpoints {
    ec2 = "http://localhost:4566"
    iam = "http://localhost:4566"
    s3  = "http://localhost:4566"
    sts = "http://localhost:4566"
  }
}

data "aws_iam_policy_document" "compute_trust" {
  statement {
    actions = ["sts:AssumeRole"]
    effect  = "Allow"

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_s3_bucket" "release" {
  bucket        = "tfpro-c60-release"
  force_destroy = true

  tags = {
    Challenge = "60"
    Component = "storage"
  }
}

resource "aws_s3_object" "manifest" {
  bucket       = aws_s3_bucket.release.id
  key          = "releases/v1/manifest.json"
  content_type = "application/json"
  content = jsonencode({
    release = "v1"
    service = "api"
  })
}

resource "aws_iam_role" "compute" {
  name               = "tfpro-c60-compute"
  assume_role_policy = data.aws_iam_policy_document.compute_trust.json

  tags = {
    Challenge = "60"
    Component = "identity"
  }
}

resource "terraform_data" "desired_capacity" {
  input = 1
}

output "monolith_contract" {
  value = {
    bucket           = aws_s3_bucket.release.id
    manifest_key     = aws_s3_object.manifest.key
    role_arn         = aws_iam_role.compute.arn
    desired_capacity = terraform_data.desired_capacity.output
  }
}

# The starter intentionally has no child modules, provider aliases, AMI/Subnet
# queries, launch template, moved blocks, or lifecycle rule.
