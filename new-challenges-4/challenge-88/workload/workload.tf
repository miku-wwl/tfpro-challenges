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
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true

  endpoints {
    ec2 = "http://localhost:4566"
    sts = "http://localhost:4566"
  }
}

variable "legacy_instance_id" {
  description = "Instance ID printed by the bootstrap root."
  type        = string

  validation {
    condition     = can(regex("^i-[0-9a-z]+$", var.legacy_instance_id))
    error_message = "legacy_instance_id must be a LocalStack EC2 instance ID."
  }
}

# Terraform 1.6 can use this declarative import block with
# plan -generate-config-out while the target resource block is still absent.
import {
  to = aws_instance.managed
  id = var.legacy_instance_id
}

# Task 3 generates a temporary resource block. Task 4 curates it to a minimal,
# stable aws_instance.managed configuration and adds the final output.
