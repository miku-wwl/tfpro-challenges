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

variable "asg_contract" {
  type = object({
    min_size         = number
    desired_capacity = number
    max_size         = number
  })

  default = {
    min_size         = 1
    desired_capacity = 1
    max_size         = 2
  }
}

data "aws_ami" "selected" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}

resource "aws_launch_template" "capacity" {
  name          = "tfpro-c35-capacity"
  image_id      = data.aws_ami.selected.id
  instance_type = "t3.micro"

  tags = {
    Challenge = "35"
    ManagedBy = "Terraform"
  }
}

resource "terraform_data" "bounds" {
  input = {
    min_size = var.asg_contract.min_size
    max_size = var.asg_contract.max_size
  }
}

resource "terraform_data" "capacity" {
  input = var.asg_contract.desired_capacity
}

output "starter_capacity_contract" {
  value = {
    launch_template = {
      id   = aws_launch_template.capacity.id
      name = aws_launch_template.capacity.name
    }
    min_size         = terraform_data.bounds.output.min_size
    desired_capacity = terraform_data.capacity.output
    max_size         = terraform_data.bounds.output.max_size
    runtime          = "terraform_data"
  }
}
