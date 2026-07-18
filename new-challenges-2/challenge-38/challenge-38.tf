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

  endpoints {
    dynamodb = "http://localhost:4566"
    s3       = "http://localhost:4566"
    sts      = "http://localhost:4566"
  }
}

variable "lease_generation" {
  type    = number
  default = 1
}

data "aws_caller_identity" "current" {}

resource "terraform_data" "lease" {
  input = {
    challenge  = 38
    generation = var.lease_generation
    account_id = data.aws_caller_identity.current.account_id
  }
}

output "starter_lease" {
  value = terraform_data.lease.output
}
