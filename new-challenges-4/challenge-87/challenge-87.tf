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

locals {
  nodes = {
    worker = "worker"
    api    = "api"
  }
}

# Apply this count-based baseline before changing its instance addresses.
resource "aws_instance" "node" {
  for_each = local.nodes

  ami           = "ami-04681a1dbd79675a5"
  instance_type = "t2.micro"

  tags = {
    Name      = "tfpro-challenge87-${each.key}"
    Challenge = "87"
    Service   = each.value
  }
}

moved {
  from = aws_instance.node[0]
  to   = aws_instance.node["api"]
}

moved {
  from = aws_instance.node[1]
  to   = aws_instance.node["worker"]
}

output "fleet_contract" {
  description = "The business-keyed view must survive the address migration."
  value = {
    for name, instance in aws_instance.node : name => {
      id   = instance.id
      name = instance.tags.Name
    }
  }
}
