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

locals {
  services = {
    dev = {
      cidr = "10.118.10.0/24"
      port = 8080
    }
    prod = {
      cidr = "10.118.20.0/24"
      port = 8443
    }
  }
}

module "service" {
  for_each = local.services
  source   = "git::https://github.com/terraform-aws-modules/terraform-aws-security-group.git?ref=v5.2.0"

  name            = "tfpro-c118-${each.key}"
  use_name_prefix = false
  vpc_id          = data.aws_subnet.selected.vpc_id
  ingress_with_cidr_blocks = [{
    from_port   = tostring(each.value.port)
    to_port     = tostring(each.value.port)
    protocol    = "tcp"
    description = "${each.key}-service"
    cidr_blocks = each.value.cidr
  }]

  tags = {
    Challenge   = "118"
    Environment = each.key
    ManagedBy   = "Terraform"
  }
}

output "service_contracts" {
  value = {
    for name, service in module.service : name => {
      id   = service.security_group_id
      name = service.security_group_name
    }
  }
}
