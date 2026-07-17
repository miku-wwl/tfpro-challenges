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

  validation {
    condition = length(var.network_matrix) > 0 && alltrue([
      for policy in values(var.network_matrix) : length(policy.cidrs) > 0 &&
      length(policy.ports) > 0 &&
      alltrue([
        for port in policy.ports : port >= 1 && port <= 65535
      ]) &&
      alltrue([
        for cidr in policy.cidrs : can(cidrnetmask(cidr))
      ]) &&
      (policy.protocol == "tcp" || policy.protocol == "udp")
    ])

    error_message = "network_matrix must be non-empty; each policy needs CIDRs and ports, ports must be 1-65535, CIDRs must be valid, and protocol must be tcp or udp."
  }
}

locals {
  ingress_rows = flatten([
    for policy_name, policy in var.network_matrix : [
      for pair in setproduct(policy.cidrs, policy.ports) : {
        key         = "${policy_name}|${pair[0]}|${pair[1]}|${policy.protocol}"
        policy      = policy_name
        cidr        = pair[0]
        port        = pair[1]
        protocol    = policy.protocol
        description = policy.description
      }
    ]
  ])

  ingress_by_key = {
    for row in local.ingress_rows : row.key => row
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

resource "aws_vpc_security_group_ingress_rule" "matrix" {
  for_each = local.ingress_by_key

  security_group_id = aws_security_group.application.id
  cidr_ipv4         = each.value.cidr
  from_port         = each.value.port
  to_port           = each.value.port
  ip_protocol       = each.value.protocol
  description       = each.value.description
}

output "starter_security_group" {
  value = {
    id     = aws_security_group.application.id
    vpc_id = aws_security_group.application.vpc_id
  }
}

# Tasks 2-5 validate and flatten network_matrix, build stable rule keys, and
# create aws_vpc_security_group_ingress_rule instances.
