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

variable "compute_spec" {
  description = "LocalStack compute selection contract used throughout the lab."

  type = object({
    ami_name_pattern  = string
    architecture      = string
    availability_zone = string
    instance_type     = string
  })

  default = {
    ami_name_pattern  = "al2023-ami-2023.*-kernel-6.1-x86_64"
    architecture      = "x86_64"
    availability_zone = "us-east-1a"
    instance_type     = "t3.micro"
  }
}

data "aws_ami" "selected" {
  most_recent = true

  filter {
    name   = "name"
    values = [var.compute_spec.ami_name_pattern]
  }

  filter {
    name   = "architecture"
    values = [var.compute_spec.architecture]
  }

  filter {
    name   = "state"
    values = ["available"]
  }

}

data "aws_caller_identity" "current" {}

output "starter_identity" {
  description = "A small executable baseline before the EC2 queries are added."
  value = {
    account_id = data.aws_caller_identity.current.account_id
    region     = "us-east-1"
  }
}

# output "selected_ami" {
#   value = {
#     id           = data.aws_ami.selected.id
#     name         = data.aws_ami.selected.name
#     architecture = data.aws_ami.selected.architecture
#   }
# }

data "aws_subnet" "selected" {
  filter {
    name   = "availability_zone"
    values = [var.compute_spec.availability_zone]
  }

  filter {
    name   = "default_for_az"
    values = ["true"]
  }
}

# output "selected_subnet" {
#   value = {
#     id                = data.aws_subnet.selected.id
#     vpc_id            = data.aws_subnet.selected.vpc_id
#     cidr_block        = data.aws_subnet.selected.cidr_block
#     availability_zone = data.aws_subnet.selected.availability_zone
#   }
# }

resource "aws_instance" "exercise" {
  ami           = data.aws_ami.selected.id
  subnet_id     = data.aws_subnet.selected.id
  instance_type = var.compute_spec.instance_type
  tags = {
    Name      = "tfpro-c81-query-contract"
    Challenge = "81"
  }
}

output "compute_contract" {
  value = {
    instance_id   = aws_instance.exercise.id
    instance_type = aws_instance.exercise.instance_type

    ami_id   = data.aws_ami.selected.id
    ami_name = data.aws_ami.selected.name

    subnet_id = aws_instance.exercise.subnet_id
    vpc_id            = data.aws_subnet.selected.vpc_id
    cidr_block        = data.aws_subnet.selected.cidr_block
    availability_zone = data.aws_subnet.selected.availability_zone

    account_id = data.aws_caller_identity.current.account_id
  }
}