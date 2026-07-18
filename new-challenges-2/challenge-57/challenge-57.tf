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
    s3  = "http://localhost:4566"
    sts = "http://localhost:4566"
  }
}

variable "workspace_contract" {
  description = "Local workload inputs used to reason about HCP workspace configuration."
  type = object({
    environment = string
    owner       = string
  })

  default = {
    environment = "dev"
    owner       = "platform"
  }
}

resource "aws_s3_bucket" "workspace_scenario" {
  bucket        = "tfpro-c57-workspace-scenario"
  force_destroy = true

  tags = {
    Challenge   = "57"
    Environment = var.workspace_contract.environment
    Owner       = var.workspace_contract.owner
  }
}

output "local_workspace_contract" {
  value = merge(var.workspace_contract, {
    bucket = aws_s3_bucket.workspace_scenario.id
  })
}
