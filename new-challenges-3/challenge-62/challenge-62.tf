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
    s3 = "http://localhost:4566"
  }
}

variable "global_tags" {
  description = "Tags inherited by every enabled team. Team tags take precedence."
  type        = map(string)
  default = {
    ManagedBy = "Terraform"
    Course    = "tfpro"
  }
}

variable "teams" {
  description = "Inline catalog to normalize with Terraform 1.6 expressions."

  type = map(object({
    enabled = bool
    paths   = set(string)
    tags    = map(string)
  }))

  default = {
    api = {
      enabled = true
      paths   = ["config/app.json", "config/routes.json"]
      tags = {
        Owner = "api-team"
        Tier  = "frontend"
      }
    }
    worker = {
      enabled = true
      paths   = ["bootstrap/init.txt"]
      tags = {
        Owner = "worker-team"
        Tier  = "backend"
      }
    }
    legacy = {
      enabled = false
      paths   = ["archive/legacy.txt"]
      tags = {
        Owner = "retired-team"
      }
    }
  }
}

resource "aws_s3_bucket" "artifacts" {
  bucket        = "tfpro-c62-artifacts"
  force_destroy = true

  tags = var.global_tags
}

locals {
  # Tasks 1-3 replace these empty starter values with a staged expression
  # pipeline: filter -> normalize -> flatten -> stable-keyed map.
  enabled_teams      = {}
  normalized_teams   = {}
  artifact_rows      = []
  artifact_instances = {}
}

# Task 4 adds one aws_s3_object resource that uses for_each over
# local.artifact_instances. The starter deliberately creates no objects.

output "enabled_team_names" {
  description = "Becomes api and worker after Task 1."
  value       = sort(keys(local.enabled_teams))
}

output "artifact_keys" {
  description = "Stable business keys produced by the completed pipeline."
  value       = sort(keys(local.artifact_instances))
}

# Task 5 adds the requested structured artifact_manifest output.
