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
  skip_region_validation      = true
  skip_requesting_account_id  = true
  s3_use_path_style           = true

  endpoints {
    s3  = "http://localhost:4566"
    sts = "http://localhost:4566"
  }
}

resource "aws_s3_bucket" "artifacts" {
  bucket        = "tfpro-c18-artifacts"
  force_destroy = true

  tags = {
    Name      = "tfpro-c18-artifacts"
    Challenge = "18"
  }
}

resource "aws_s3_object" "release" {
  bucket  = aws_s3_bucket.artifacts.id
  key     = "releases/current.txt"
  content = "release=tfpro-c18-starter"

  tags = {
    Challenge = "18"
  }
}

resource "aws_s3_bucket" "audit" {
  bucket        = "tfpro-c18-audit"
  force_destroy = true

  tags = {
    Name      = "tfpro-c18-audit"
    Challenge = "18"
  }
}

output "dependency_contract" {
  description = "Names used to verify the complete dependency graph."
  value = {
    artifact_bucket = aws_s3_bucket.artifacts.id
    object_key      = aws_s3_object.release.key
    audit_bucket    = aws_s3_bucket.audit.id
  }
}
