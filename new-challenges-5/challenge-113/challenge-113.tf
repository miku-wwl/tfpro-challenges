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

module "http_80" {
  source = "git::https://github.com/terraform-aws-modules/terraform-aws-security-group.git//modules/http-80?ref=v5.2.0"

  name            = "tfpro-c113-http-80"
  use_name_prefix = false
  description     = "Challenge 113 Git subdirectory HTTP access"
  vpc_id          = data.aws_subnet.selected.vpc_id

  ingress_cidr_blocks = ["10.113.0.0/16"]

  tags = {
    Challenge = "113"
    ManagedBy = "Terraform"
  }
}

output "http_contract" {
  description = "Nested-module security-group identity and API acceptance contract."
  value = {
    security_group_id = module.http_80.security_group_id
    name              = module.http_80.security_group_name
    vpc_id            = data.aws_subnet.selected.vpc_id
    ingress_cidr      = "10.113.0.0/16"
    ingress_port      = 80
  }
}
