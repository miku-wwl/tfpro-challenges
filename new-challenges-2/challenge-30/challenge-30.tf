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
    s3 = "http://localhost:4566"
  }
}

variable "feature" {
  description = "A zero-or-one feature contract. The starter deliberately leaves it disabled."
  type = object({
    enabled     = bool
    bucket_name = string
    marker_key  = string
  })

  default = {
    enabled     = false
    bucket_name = "tfpro-c30-optional"
    marker_key  = "enabled.txt"
  }
}

output "starter_contract" {
  description = "A resource-free baseline; replace this with the final nullable feature contract."
  value = {
    enabled     = var.feature.enabled
    bucket_name = var.feature.bucket_name
    marker_key  = var.feature.marker_key
  }
}
