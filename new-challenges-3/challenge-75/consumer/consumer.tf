terraform {
  required_version = "~> 1.6.0"

  backend "s3" {
    region = "us-east-1"

    endpoints = {
      s3 = "http://localhost:4566"
    }

    use_path_style              = true
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    skip_s3_checksum            = true
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

variable "expected_release" {
  description = "Consumer 明确接受的 Producer 发布版本。"
  type        = string
  default     = "v1"

  validation {
    condition     = contains(["v1", "v2"], var.expected_release)
    error_message = "expected_release 只能是 v1 或 v2。"
  }
}

locals {
  # 这是待迁移的旧式复制合同。Task 4 必须删除它，并改读 Producer remote state。
  legacy_contract = {
    schema_version = 1
    release        = "v1"
    bucket         = "tfpro-challenge75-release"
    object_key     = "manifest.json"
    payload_sha256 = sha256(jsonencode({
      application = "payments"
      release     = "v1"
    }))
  }

  contract = local.legacy_contract
}

resource "aws_s3_bucket" "receipts" {
  bucket        = "tfpro-challenge75-receipts"
  force_destroy = true

  tags = {
    Challenge = "75"
    Owner     = "consumer"
  }
}

resource "aws_s3_object" "receipt" {
  bucket  = aws_s3_bucket.receipts.id
  key     = "producer-receipt.json"
  content = jsonencode(local.contract)
  etag    = md5(jsonencode(local.contract))

  lifecycle {
    precondition {
      condition     = local.contract.schema_version == 1
      error_message = "Producer 合同 schema_version 必须为 1。"
    }

    precondition {
      condition     = local.contract.release == var.expected_release
      error_message = "Producer release 与 Consumer expected_release 不一致。"
    }
  }
}

output "consumed_contract" {
  description = "Consumer 实际物化到 receipt 的合同。"
  value       = local.contract
}
