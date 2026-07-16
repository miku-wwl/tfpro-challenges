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
  s3_use_path_style           = true
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true

  endpoints {
    iam = "http://localhost:4566"
    s3  = "http://localhost:4566"
  }
}

resource "aws_s3_bucket" "release" {
  bucket        = "tfpro-c64-release"
  force_destroy = true

  tags = {
    ManagedBy = "Terraform"
    Challenge = "64"
  }
}

data "aws_iam_policy_document" "assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "reader" {
  name               = "tfpro-c64-reader"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
}

data "aws_iam_policy_document" "read_release" {
  statement {
    sid       = "ReadReleaseObjects"
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.release.arn}/*"]
  }
}

resource "aws_iam_policy" "reader" {
  name   = "tfpro-c64-read-release"
  policy = data.aws_iam_policy_document.read_release.json
}

resource "aws_iam_role_policy_attachment" "reader" {
  role       = aws_iam_role.reader.name
  policy_arn = aws_iam_policy.reader.arn
}

resource "aws_s3_object" "ready" {
  bucket       = aws_s3_bucket.release.id
  key          = "status/ready.json"
  content      = jsonencode({ status = "ready" })
  content_type = "application/json"

  # Task 2 adds the one non-redundant explicit dependency in this challenge.
  # This marker must be published only after the reader policy is attached.
}

resource "aws_s3_object" "notes" {
  bucket       = aws_s3_bucket.release.id
  key          = "releases/notes.txt"
  content      = "Challenge 64 release notes"
  content_type = "text/plain"
}

output "release_contract" {
  description = "Addresses and remote keys used in the partial/full apply checks."
  value = {
    bucket = aws_s3_bucket.release.bucket
    ready  = aws_s3_object.ready.key
    notes  = aws_s3_object.notes.key
    role   = aws_iam_role.reader.name
  }
}
