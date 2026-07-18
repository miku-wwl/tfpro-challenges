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

variable "ingress_rules" {
  type = map(object({
    description = string
    protocol    = string
    from_port   = number
    to_port     = number
    cidr_ipv4   = string
  }))

  default = {
    web = {
      description = "Public HTTP"
      protocol    = "tcp"
      from_port   = 80
      to_port     = 80
      cidr_ipv4   = "0.0.0.0/0"
    }
    metrics = {
      description = "Internal metrics"
      protocol    = "tcp"
      from_port   = 9090
      to_port     = 9090
      cidr_ipv4   = "10.0.0.0/8"
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

resource "aws_security_group" "app" {
  name        = "tfpro-c32-rules"
  description = "Rule migration exercise"
  vpc_id      = data.aws_subnet.selected.vpc_id

  tags = {
    Name      = "tfpro-c32-rules"
    Challenge = "32"
  }
}

resource "aws_security_group_rule" "legacy" {
  for_each = var.ingress_rules

  type              = "ingress"
  security_group_id = aws_security_group.app.id
  description       = each.value.description
  protocol          = each.value.protocol
  from_port         = each.value.from_port
  to_port           = each.value.to_port
  cidr_blocks       = [each.value.cidr_ipv4]
}

output "starter_security_group" {
  value = {
    id        = aws_security_group.app.id
    name      = aws_security_group.app.name
    rule_keys = sort(keys(var.ingress_rules))
  }
}
