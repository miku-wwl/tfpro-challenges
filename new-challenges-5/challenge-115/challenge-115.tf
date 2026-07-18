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
  source = "git::https://github.com/hashicorp/terraform-cidr-subnets.git?ref=v1.0.0"

  base_cidr_block = "10.115.0.0/16"
  networks = [
    { name = "app", new_bits = 8 },
    { name = "data", new_bits = 8 },
  ]
}

resource "aws_s3_bucket" "evidence" {
  bucket        = "tfpro-c115-git-version-boundary"
  force_destroy = true

  tags = {
    Challenge = "115"
    ManagedBy = "Terraform"
  }
}

output "starter_network_contract" {
  value = {
    bucket = aws_s3_bucket.evidence.id
    cidrs  = module.network.network_cidr_blocks
  }
}
