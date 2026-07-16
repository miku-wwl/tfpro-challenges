terraform {
  required_version = "~> 1.6.0"

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

resource "aws_instance" "workload" {
  ami           = "ami-04681a1dbd79675a5"
  instance_type = "t2.micro"

  tags = {
    Name      = "tfpro-challenge89-workload"
    Challenge = "89"
    Owner     = "platform-team"
    Release   = "v1"
  }
}

output "instance_contract" {
  description = "Compare this state-backed contract with the EC2 API during drift recovery."
  value = {
    id   = aws_instance.workload.id
    tags = aws_instance.workload.tags
  }
}
