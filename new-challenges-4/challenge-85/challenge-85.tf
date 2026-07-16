terraform {

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

variable "availability_zone" {
  type    = string
  default = "us-east-1a"
}

variable "network_matrix" {
  description = "Policies expand to one ingress rule for every CIDR/port pair."

  type = map(object({
    cidrs       = set(string)
    ports       = set(number)
    protocol    = optional(string, "tcp")
    description = string
  }))

  default = {
    web = {
      cidrs       = ["10.20.0.0/24", "10.30.0.0/24"]
      ports       = [80, 443]
      description = "application traffic"
    }

    admin = {
      cidrs       = ["203.0.113.10/32"]
      ports       = [22]
      description = "restricted administration"
    }
  }
}

data "aws_subnet" "selected" {
  filter {
    name   = "availability-zone"
    values = [var.availability_zone]
  }

  filter {
    name   = "default-for-az"
    values = ["true"]
  }
}

resource "aws_security_group" "application" {
  name        = "tfpro-c85-network-matrix"
  description = "Ingress is added from the HCL network matrix during the lab."
  vpc_id      = data.aws_subnet.selected.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Challenge = "85"
  }
}

output "starter_security_group" {
  value = {
    id     = aws_security_group.application.id
    vpc_id = aws_security_group.application.vpc_id
  }
}

# Tasks 2-5 validate and flatten network_matrix, build stable rule keys, and
# create aws_vpc_security_group_ingress_rule instances.
