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
    iam = "http://localhost:4566"
    s3  = "http://localhost:4566"
    sts = "http://localhost:4566"
  }
}

resource "aws_s3_bucket" "storage" {
  bucket        = "tfpro-c45-storage"
  force_destroy = true

  tags = {
    Name      = "tfpro-c45-storage"
    Challenge = "45"
    Release   = "v1"
  }
}

resource "aws_iam_role" "publisher" {
  name = "tfpro-c45-publisher"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_policy" "publisher" {
  name = "tfpro-c45-put-objects"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "PublishObjects"
      Effect   = "Allow"
      Action   = ["s3:PutObject"]
      Resource = format("%s/*", aws_s3_bucket.storage.arn)
    }]
  })
}

resource "aws_iam_role_policy_attachment" "publisher" {
  role       = aws_iam_role.publisher.name
  policy_arn = aws_iam_policy.publisher.arn
}

output "starter_composition" {
  value = {
    storage = {
      name = aws_s3_bucket.storage.bucket
      arn  = aws_s3_bucket.storage.arn
    }
    publisher = {
      role_name  = aws_iam_role.publisher.name
      role_arn   = aws_iam_role.publisher.arn
      policy_arn = aws_iam_policy.publisher.arn
    }
  }
}
