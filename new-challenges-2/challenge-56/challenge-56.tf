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

variable "release" {
  description = "Small workload change used to ground the HCP run scenarios."
  type        = string
  default     = "v1"
}

resource "aws_s3_bucket" "run_scenario" {
  bucket        = "tfpro-c56-run-scenario"
  force_destroy = true

  tags = {
    Challenge = "56"
    Release   = var.release
  }
}

output "local_run_contract" {
  value = {
    bucket  = aws_s3_bucket.run_scenario.id
    release = aws_s3_bucket.run_scenario.tags["Release"]
  }
}
