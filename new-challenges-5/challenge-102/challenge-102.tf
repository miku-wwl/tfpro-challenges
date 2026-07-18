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

module "web" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "5.1.0"

  name            = "tfpro-c102-web"
  description     = "Challenge 102 versioned Registry module"
  vpc_id          = data.aws_subnet.selected.vpc_id
  use_name_prefix = false

  ingress_with_cidr_blocks = [
    {
      from_port   = 443
      to_port     = 443
      protocol    = "tcp"
      description = "HTTPS from challenge 102"
      cidr_blocks = "10.102.0.0/16"
    }
  ]

  egress_rules = ["all-all"]

  tags = {
    Challenge = "102"
    ManagedBy = "Terraform"
  }
}

output "security_group_contract" {
  value = {
    id      = module.web.security_group_id
    name    = module.web.security_group_name
    vpc_id  = module.web.security_group_vpc_id
    purpose = "registry-version-upgrade"
  }
}
