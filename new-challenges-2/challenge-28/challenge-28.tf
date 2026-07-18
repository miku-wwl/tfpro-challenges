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

variable "artifacts" {
  description = "Raw artifact input that you will normalize, filter, enrich, and encode."
  type = list(object({
    logical_name = string
    object_key   = string
    content      = string
    enabled      = bool
    tags         = map(string)
  }))

  default = [
    {
      logical_name = " Read Me "
      object_key   = " docs/README.TXT "
      content      = "Terraform Professional practice"
      enabled      = true
      tags         = { Tier = "Docs" }
    },
    {
      logical_name = "App Config"
      object_key   = " config/APP.JSON "
      content      = "{\"enabled\":true}"
      enabled      = true
      tags         = { Tier = "Config" }
    },
    {
      logical_name = "Draft Notes"
      object_key   = " drafts/NOTES.TXT "
      content      = "not published"
      enabled      = false
      tags         = { Tier = "Docs" }
    }
  ]
}

locals {
  common_tags = {
    Challenge = "28"
    ManagedBy = "terraform"
  }
}

resource "aws_s3_bucket" "artifacts" {
  bucket = "tfpro-c28-function-pipeline"

  tags = local.common_tags
}

output "pipeline_starter" {
  description = "Only the destination exists initially; tasks add the transformation pipeline and objects."
  value = {
    bucket         = aws_s3_bucket.artifacts.id
    raw_item_count = length(var.artifacts)
    enabled_count  = length([for item in var.artifacts : item if item.enabled])
  }
}
