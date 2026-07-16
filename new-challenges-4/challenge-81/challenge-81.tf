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

variable "compute_spec" {
  description = "LocalStack compute selection contract used throughout the lab."

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
  description = "A small executable baseline before the EC2 queries are added."
  value = {
    account_id = data.aws_caller_identity.current.account_id
    region     = "us-east-1"
  }
}

# Tasks 2-5 add the AMI query, subnet query, EC2 instance, and final contract.
