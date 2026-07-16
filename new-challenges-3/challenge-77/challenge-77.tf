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

module "api" {
  source = "./modules/release"

  bucket_name = "tfpro-challenge77-api"
  owner       = "api-team"
}

module "worker" {
  source = "./modules/release"

  bucket_name = "tfpro-challenge77-worker"
  owner       = "worker-team"
}

output "release_buckets" {
  value = {
    api    = module.api.bucket_id
    worker = module.worker.bucket_id
  }
}
