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

module "edge" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "5.2.0"

  name            = "tfpro-c117-source-switch"
  use_name_prefix = false
  vpc_id          = data.aws_subnet.selected.vpc_id
  ingress_with_cidr_blocks = [{
    from_port   = "443"
    to_port     = "443"
    protocol    = "tcp"
    description = "registry-to-git"
    cidr_blocks = "10.117.0.0/16"
  }]

  tags = {
    Challenge = "117"
    ManagedBy = "Terraform"
  }
}

output "edge_contract" {
  value = {
    id     = module.edge.security_group_id
    name   = module.edge.security_group_name
    vpc_id = module.edge.security_group_vpc_id
    source = "registry"
  }
}
