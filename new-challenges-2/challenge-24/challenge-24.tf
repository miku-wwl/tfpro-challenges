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
  skip_region_validation      = true
  skip_requesting_account_id  = true

  endpoints {
    ec2 = "http://localhost:4566"
  }
}

data "aws_ami" "selected" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-kernel-6.1-x86_64"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}

resource "aws_instance" "exercise" {
  ami           = data.aws_ami.selected.id
  instance_type = "t3.micro"

  tags = {
    Name      = "tfpro-c24-replace"
    Challenge = "24"
  }
}

output "instance_contract" {
  description = "Stable settings plus the provider-assigned identity used as replacement evidence."
  value = {
    id            = aws_instance.exercise.id
    ami           = aws_instance.exercise.ami
    instance_type = aws_instance.exercise.instance_type
  }
}
