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

  endpoints {
    iam = "http://localhost:4566"
    sts = "http://localhost:4566"
  }
}

data "aws_caller_identity" "current" {}

resource "aws_iam_user" "kplabs_user" {
  name = "kplabs-challenge35-user"
}

resource "aws_iam_user" "ro_user" {
  name = "ro-user-challenge35"
}

resource "aws_iam_policy" "assume_role_policy" {
  name = "Challenge35AssumeRolePolicy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "sts:AssumeRole"
      Resource = "*"
    }]
  })
}

resource "aws_iam_policy_attachment" "kplabs_attach" {
  name       = "challenge35-kplabs-attachment"
  users      = [aws_iam_user.kplabs_user.name]
  policy_arn = aws_iam_policy.assume_role_policy.arn
}

resource "aws_iam_policy_attachment" "ro_attach" {
  name       = "challenge35-ro-attachment"
  users      = [aws_iam_user.ro_user.name]
  policy_arn = aws_iam_policy.assume_role_policy.arn
}

resource "aws_iam_access_key" "kplabs_user_key" {
  user = aws_iam_user.kplabs_user.name
}

resource "aws_iam_access_key" "ro_user_key" {
  user = aws_iam_user.ro_user.name
}

resource "aws_iam_role" "compute_full_access" {
  name = "EC2FullAccessChallenge35"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:user/${aws_iam_user.kplabs_user.name}"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role" "iam_full_access" {
  name = "IAMFullAccessChallenge35"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:user/${aws_iam_user.kplabs_user.name}"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role" "read_only_role" {
  name = "ReadOnlyRoleChallenge35"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:user/${aws_iam_user.ro_user.name}"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ec2" {
  role       = aws_iam_role.compute_full_access.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2FullAccess"
}

resource "aws_iam_role_policy_attachment" "iam" {
  role       = aws_iam_role.iam_full_access.name
  policy_arn = "arn:aws:iam::aws:policy/IAMFullAccess"
}

resource "aws_iam_role_policy_attachment" "read_only" {
  role       = aws_iam_role.read_only_role.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

output "compute_full_access_role_arn" {
  value = aws_iam_role.compute_full_access.arn
}

output "iam_full_access_role_arn" {
  value = aws_iam_role.iam_full_access.arn
}

output "read_only_role_arn" {
  value = aws_iam_role.read_only_role.arn
}
