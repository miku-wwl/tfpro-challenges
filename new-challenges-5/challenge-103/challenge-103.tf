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
  skip_requesting_account_id  = true

  endpoints {
    ec2 = "http://localhost:4566"
    sts = "http://localhost:4566"
  }
}

variable "security_group_contract" {
  type = object({
    name        = string
    description = string
    ingress = list(object({
      name        = string
      from_port   = number
      to_port     = number
      protocol    = string
      cidr_block  = string
      description = string
    }))
    tags = map(string)
  })

  default = {
    name        = "tfpro-c103-application"
    description = "Challenge 103 complex input contract"
    ingress = [
      {
        name        = "https"
        from_port   = 443
        to_port     = 443
        protocol    = "tcp"
        cidr_block  = "10.103.0.0/16"
        description = "HTTPS application traffic"
      },
      {
        name        = "admin"
        from_port   = 8443
        to_port     = 8443
        protocol    = "tcp"
        cidr_block  = "10.103.10.0/24"
        description = "Restricted administration traffic"
      }
    ]
    tags = {
      Challenge = "103"
      ManagedBy = "Terraform"
    }
  }
}

data "aws_subnet" "selected" {
  filter {
    name   = "availability-zone"
    values = ["us-east-1a"]
  }

  filter {
    name   = "default-for-az"
    values = ["true"]
  }
}

output "starter_input_contract" {
  value = {
    requested = var.security_group_contract
    vpc_id    = data.aws_subnet.selected.vpc_id
  }
}
