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
    s3  = "http://localhost:4566"
    sts = "http://localhost:4566"
  }
}

module "network" {
  source = "git::https://github.com/hashicorp/terraform-cidr-subnets.git"

  base_cidr_block = "10.116.0.0/16"
  networks = [
    { name = "public", new_bits = 8 },
    { name = "private", new_bits = 8 },
  ]
}

resource "aws_s3_bucket" "evidence" {
  bucket        = "tfpro-c116-unpinned-git"
  force_destroy = true

  tags = {
    Challenge = "116"
    ManagedBy = "Terraform"
  }
}

resource "aws_s3_object" "contract" {
  bucket       = aws_s3_bucket.evidence.id
  key          = "network.json"
  content      = jsonencode(module.network.network_cidr_blocks)
  content_type = "application/json"
}

output "git_network_contract" {
  value = {
    bucket = aws_s3_bucket.evidence.id
    key    = aws_s3_object.contract.key
    cidrs  = module.network.network_cidr_blocks
  }
}
