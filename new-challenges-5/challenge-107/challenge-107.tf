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

variable "edge_enabled" {
  description = "Whether the edge security-group module instance exists."
  type        = bool
  default     = true
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

  count = var.edge_enabled ? 1 : 0

  name            = "tfpro-c107-edge"
  use_name_prefix = false
  description     = "Challenge 107 edge HTTP access"
  vpc_id          = data.aws_subnet.selected.vpc_id

  ingress_cidr_blocks = ["10.107.0.0/16"]
  ingress_rules       = ["http-80-tcp"]
  egress_rules        = ["all-all"]

  tags = {
    Challenge = "107"
    ManagedBy = "Terraform"
  }
}

output "edge_contract" {
  description = "Stable remote identity while the module instance address is refactored."
  value = {
    enabled           = var.edge_enabled
    security_group_id = try(module.edge[0].security_group_id, null)
    name              = try(module.edge[0].security_group_name, null)
    vpc_id            = data.aws_subnet.selected.vpc_id
  }
}
