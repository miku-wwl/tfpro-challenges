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

  endpoints {
    ec2 = "http://localhost:4566"
    sts = "http://localhost:4566"
  }
}

variable "compute_request" {
  description = "Selection criteria that data sources will turn into an EC2 contract."
  type = object({
    ami_name_pattern  = string
    architecture      = string
    availability_zone = string
    instance_type     = string
  })

  default = {
    ami_name_pattern  = "al2023-ami-2023.*-kernel-6.1-x86_64"
    architecture      = "x86_64"
    availability_zone = "us-east-1a"
    instance_type     = "t3.micro"
  }
}

data "aws_caller_identity" "current" {}

output "starter_identity" {
  description = "A runnable read-only baseline before AMI, subnet, and instance blocks are added."
  value = {
    account_id = data.aws_caller_identity.current.account_id
    region     = "us-east-1"
  }
}
