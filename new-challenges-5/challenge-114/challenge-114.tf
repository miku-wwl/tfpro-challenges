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
  source = "git::https://github.com/terraform-aws-modules/terraform-aws-security-group.git//modules/http-80?ref=v5.2.0"

  name                = "tfpro-c114-web"
  use_name_prefix     = false
  vpc_id              = data.aws_subnet.selected.vpc_id
  ingress_cidr_blocks = ["10.114.0.0/16"]

  tags = {
    Challenge = "114"
    ManagedBy = "Terraform"
  }
}

output "starter_web_contract" {
  value = {
    security_group_id   = module.web.security_group_id
    security_group_name = module.web.security_group_name
    vpc_id              = module.web.security_group_vpc_id
    source_kind         = "git-subdirectory"
  }
}
