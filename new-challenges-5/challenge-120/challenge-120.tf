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
    ec2 = "http://localhost:4566"
    s3  = "http://localhost:4566"
    sts = "http://localhost:4566"
  }
}

data "aws_subnet" "selected" {
  filter {
    name   = "availability-zone"
    values = ["us-east-1a"]
  }

  filter {
    name   = "default-for-az"
    values = ["true"]
  }
}

resource "aws_s3_bucket" "evidence" {
  bucket        = "tfpro-c120-multi-source"
  force_destroy = true

  tags = {
    Challenge = "120"
    ManagedBy = "Terraform"
  }
}

output "starter_evidence" {
  value = {
    bucket    = aws_s3_bucket.evidence.id
    subnet_id = data.aws_subnet.selected.id
    vpc_id    = data.aws_subnet.selected.vpc_id
  }
}
