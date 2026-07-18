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

module "cidr" {
  source  = "hashicorp/subnets/cidr"
  version = "1.0.0"

  base_cidr_block = "10.109.0.0/16"
  networks = [
    {
      name     = "web"
      new_bits = 8
    },
    {
      name     = "app"
      new_bits = 8
    },
    {
      name     = "data"
      new_bits = 8
    }
  ]
}

resource "aws_s3_bucket" "contract" {
  bucket        = "tfpro-c109-module-cache"
  force_destroy = true

  tags = {
    Challenge = "109"
    ManagedBy = "Terraform"
  }
}

resource "aws_s3_object" "network_contract" {
  bucket       = aws_s3_bucket.contract.id
  key          = "network-contract.json"
  content_type = "application/json"
  content = jsonencode({
    challenge = "109"
    networks  = module.cidr.network_cidr_blocks
  })
}

output "cache_contract" {
  description = "Remote contract that must not change while the local module cache is rebuilt."
  value = {
    bucket   = aws_s3_bucket.contract.id
    key      = aws_s3_object.network_contract.key
    networks = module.cidr.network_cidr_blocks
  }
}
