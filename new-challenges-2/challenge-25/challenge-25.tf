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

variable "release_version" {
  description = "A source-controlled release revision used by the replacement exercise."
  type        = string
  default     = "v1"
}

resource "terraform_data" "release" {
  input            = var.release_version
  triggers_replace = [var.release_version]
}

resource "aws_s3_bucket" "guarded" {
  bucket = "tfpro-c25-guarded"

  tags = {
    Name            = "tfpro-c25-guarded"
    Challenge       = "25"
    OperationalMode = "managed"
  }
}

resource "aws_s3_object" "marker" {
  bucket  = aws_s3_bucket.guarded.id
  key     = "release-marker.txt"
  content = "lifecycle guardrail marker"

  tags = {
    Challenge = "25"
  }
}

output "guardrail_baseline" {
  description = "A baseline that becomes lifecycle-aware as you complete the tasks."
  value = {
    bucket          = aws_s3_bucket.guarded.id
    marker_etag     = aws_s3_object.marker.etag
    release_version = terraform_data.release.output
  }
}
