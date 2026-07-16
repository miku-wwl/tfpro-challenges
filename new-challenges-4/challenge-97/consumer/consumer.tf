terraform {

  backend "s3" {
    key                         = "challenge97/consumer.tfstate"
    region                      = "us-east-1"
    use_path_style              = true
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    skip_s3_checksum            = true
    endpoints = {
      s3 = "http://localhost:4566"
    }
  }

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

data "terraform_remote_state" "producer" {
  backend = "s3"

  config = {
    bucket                      = "tfpro-c97-state"
    key                         = "challenge97/producer.tfstate"
    region                      = "us-east-1"
    use_path_style              = true
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    skip_s3_checksum            = true
    endpoints = {
      s3 = "http://localhost:4566"
    }
  }

  defaults = {
    retention_policy = {
      schema_version = 1
      days           = 7
      source         = "consumer-default"
    }
  }
}

locals {
  release_contract = data.terraform_remote_state.producer.outputs.release_contract
  retention_policy = data.terraform_remote_state.producer.outputs.retention_policy
}

resource "aws_s3_object" "consumer_manifest" {
  bucket       = local.release_contract.bucket
  key          = "${local.release_contract.prefix}consumer-retention.json"
  content_type = "application/json"
  content = jsonencode({
    schema_version = local.retention_policy.schema_version
    retention_days = local.retention_policy.days
    source         = local.retention_policy.source
  })

  lifecycle {
    precondition {
      condition     = local.retention_policy.schema_version == 1
      error_message = "The consumer only accepts retention_policy schema_version 1."
    }
  }
}

output "consumed_policy" {
  value = local.retention_policy
}
