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

variable "environments" {
  type = map(object({
    name        = string
    description = string
    port        = number
    cidr_block  = string
  }))

  default = {
    dev = {
      name        = "tfpro-c105-dev"
      description = "Challenge 105 development access"
      port        = 8080
      cidr_block  = "10.105.10.0/24"
    }
    prod = {
      name        = "tfpro-c105-prod"
      description = "Challenge 105 production access"
      port        = 443
      cidr_block  = "10.105.20.0/24"
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

module "security_groups" {
  for_each = var.environments

  source  = "terraform-aws-modules/security-group/aws"
  version = "5.2.0"

  name            = each.value.name
  description     = each.value.description
  vpc_id          = data.aws_subnet.selected.vpc_id
  use_name_prefix = false

  ingress_with_cidr_blocks = [
    {
      from_port   = each.value.port
      to_port     = each.value.port
      protocol    = "tcp"
      description = "${each.key} managed access"
      cidr_blocks = each.value.cidr_block
    }
  ]

  egress_rules = ["all-all"]

  tags = {
    Challenge   = "105"
    Environment = each.key
    ManagedBy   = "Terraform"
  }
}
