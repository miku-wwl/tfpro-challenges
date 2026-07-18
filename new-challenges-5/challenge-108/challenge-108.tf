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

module "baseline" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "5.2.0"

  name            = "tfpro-c108-version-boundary"
  use_name_prefix = false
  description     = "Challenge 108 compatible module baseline"
  vpc_id          = data.aws_subnet.selected.vpc_id

  ingress_cidr_blocks = ["10.108.0.0/16"]
  ingress_rules       = ["https-443-tcp"]
  egress_rules        = ["all-all"]

  tags = {
    Challenge = "108"
    ManagedBy = "Terraform"
  }
}

output "security_group_contract" {
  description = "Identity that must survive the failed module-upgrade experiment."
  value = {
    security_group_id = module.baseline.security_group_id
    name              = module.baseline.security_group_name
    vpc_id            = data.aws_subnet.selected.vpc_id
    module_version    = "5.2.0"
    provider_version  = "5.80.0"
  }
}
