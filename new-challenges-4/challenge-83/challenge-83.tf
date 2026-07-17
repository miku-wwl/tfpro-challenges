terraform {

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.80.0"
    }

    random = {
      source  = "hashicorp/random"
      version = "3.9.0"
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

variable "service_names" {
  description = "Public logical identities. These are valid resource keys."
  type        = set(string)
  default     = ["api", "worker"]
}

variable "service_tokens" {
  description = "LocalStack-only sample secrets. Values must never become resource keys."
  type        = map(string)
  sensitive   = true

  default = {
    api    = "local-only-api-token"
    worker = "local-only-worker-token"
  }
}

resource "aws_s3_bucket" "inventory" {
  bucket        = "tfpro-c83-plan-time-keys"
  force_destroy = true

  tags = {
    Challenge = "83"
  }
}

output "starter_bucket" {
  value = aws_s3_bucket.inventory.id
}

resource "random_integer" "shard" {
  for_each = var.service_names

  min = 100
  max = 999

  keepers = {
    name = each.key
  }
}

resource "aws_s3_object" "manifest" {
  for_each = { for service in var.service_names : service => service }

  key    = "manifests/${each.key}.json"
  bucket = aws_s3_bucket.inventory.id

  content = jsonencode({
    service              = each.key
    random               = random_integer.shard[each.key].result
    sha256_service_token = sha256(var.service_tokens[each.key])
  })

}


output "manifest_keys" {
  value = sort([
    for service in var.service_names : "manifests/${service}.json"
  ])
}

output "shard_contract" {
  value = {
    for service in var.service_names : service => random_integer.shard[service].result
  }
}