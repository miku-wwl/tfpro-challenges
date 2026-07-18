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
  alias                       = "primary"
  region                      = "us-east-1"
  access_key                  = "test"
  secret_key                  = "test"
  s3_use_path_style           = true
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true

  endpoints {
    s3  = "http://localhost:4566"
    sts = "http://localhost:4566"
  }
}

provider "aws" {
  alias                       = "dr"
  region                      = "us-west-2"
  access_key                  = "test"
  secret_key                  = "test"
  s3_use_path_style           = true
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true

  endpoints {
    s3  = "http://localhost:4566"
    sts = "http://localhost:4566"
  }
}

resource "aws_s3_bucket" "primary" {
  provider      = aws.primary
  bucket        = "tfpro-c49-primary"
  force_destroy = true

  tags = {
    Challenge  = "49"
    RegionRole = "primary"
  }
}

resource "aws_s3_bucket" "dr" {
  provider      = aws.dr
  bucket        = "tfpro-c49-dr"
  force_destroy = true

  tags = {
    Challenge  = "49"
    RegionRole = "dr"
  }
}

output "starter_buckets" {
  value = {
    primary = aws_s3_bucket.primary.id
    dr      = aws_s3_bucket.dr.id
  }
}

# Tasks move both resources into one temporary child module with two
# configuration_aliases and preserve both physical bucket IDs.
