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

variable "compute" {
  description = "A compute contract with defaults for omission and null-preserving optional fields."

  type = object({
    name              = string
    instance_type     = optional(string, "t3.micro")
    availability_zone = optional(string, "us-east-1a")
    user_data         = optional(string)
    tags              = optional(map(string), {})
  })

  default = {
    name = "tfpro-c84-default"
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

data "aws_subnet" "selected" {
  filter {
    name   = "availability-zone"
    values = [var.compute.availability_zone]
  }

  filter {
    name   = "default-for-az"
    values = ["true"]
  }
}

resource "aws_instance" "exercise" {
  ami           = data.aws_ami.selected.id
  instance_type = var.compute.instance_type
  subnet_id     = data.aws_subnet.selected.id
  user_data     = var.compute.user_data

  tags = merge(
    {
      Name      = var.compute.name
      Challenge = "84"
    },
    var.compute.tags,
  )
}

output "starter_instance" {
  value = {
    id            = aws_instance.exercise.id
    name          = var.compute.name
    instance_type = var.compute.instance_type
  }
}

# Tasks 2-5 add validation and a normalized contract, then exercise default,
# TF_VAR_compute, and -var precedence without committing any tfvars files.
