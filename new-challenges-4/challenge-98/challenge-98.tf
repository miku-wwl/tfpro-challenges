terraform {
  required_version = "~> 1.6.0"

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

variable "release_serial" {
  description = "Increment this value during Task 2 to create the v2 release plan."
  type        = number
  default     = 1

  validation {
    condition     = var.release_serial >= 1 && floor(var.release_serial) == var.release_serial
    error_message = "release_serial must be a positive whole number."
  }
}

variable "bootstrap_token" {
  description = "A fake LocalStack-only value used to inspect sensitive markers in plan JSON."
  type        = string
  sensitive   = true
  default     = "fake-localstack-token-c98"
}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-trusty-14.04-amd64-server-*"]
  }
}

locals {
  bootstrap_payload = jsonencode({
    release_serial = var.release_serial
    token          = var.bootstrap_token
  })
}

resource "aws_instance" "release" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = "t2.micro"
  user_data                   = local.bootstrap_payload
  user_data_replace_on_change = true

  tags = {
    Name      = "tfpro-c98-release"
    Challenge = "98"
    Serial    = tostring(var.release_serial)
  }
}

output "release_contract" {
  description = "Non-sensitive deployment identity used by the final checks."
  value = {
    instance_id = aws_instance.release.id
    serial      = var.release_serial
    ami_id      = data.aws_ami.ubuntu.id
  }
}
