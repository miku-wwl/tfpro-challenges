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

provider "aws" {
  alias                       = "primary"
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
  provider = aws.primary

  filter {
    name   = "availability-zone"
    values = ["us-east-1a"]
  }

  filter {
    name   = "default-for-az"
    values = ["true"]
  }
}

module "application" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "5.2.0"

  name            = "tfpro-c106-application"
  description     = "Challenge 106 default-provider baseline"
  vpc_id          = data.aws_subnet.selected.vpc_id
  use_name_prefix = false

  ingress_with_cidr_blocks = [
    {
      from_port   = 443
      to_port     = 443
      protocol    = "tcp"
      description = "Application HTTPS"
      cidr_blocks = "10.106.0.0/16"
    }
  ]

  egress_rules = ["all-all"]

  tags = {
    Challenge = "106"
    ManagedBy = "Terraform"
  }
}

output "starter_provider_contract" {
  value = {
    module_name     = module.application.security_group_name
    security_group  = module.application.security_group_id
    vpc_id          = data.aws_subnet.selected.vpc_id
    module_provider = "default"
  }
}
