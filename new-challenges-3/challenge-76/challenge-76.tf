terraform {

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

variable "release_version" {
  description = "Version written to the current release object."
  type        = string
  default     = "v1"
}

locals {
  bucket_name = "tfpro-challenge76-artifacts"
}

module "storage" {
  source = "./modules/storage"

  bucket_name = local.bucket_name
}

# The publisher currently receives a duplicated string and needs an explicit
# dependency. Tasks 2-4 replace this weak interface with a typed module output.
module "publisher" {
  source = "./modules/publisher"

  bucket_name = local.bucket_name
  object_key  = "releases/current.txt"
  content     = var.release_version

  depends_on = [module.storage]
}

output "release_location" {
  description = "Initial root-level release location."
  value = {
    bucket = local.bucket_name
    key    = module.publisher.object_key
  }
}
