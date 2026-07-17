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

  validation {
    condition     = can(regex("^[a-zA-Z0-9-]+$", var.compute.name)) && length(var.compute.name) >= 3 && length(var.compute.name) <= 40
    error_message = "name can only contain characters, numbers and -, the range of the length is between 3 and 40"
  }

  validation {
    condition     = var.compute.instance_type == "t3.micro" || var.compute.instance_type == "t3.small"
    error_message = "instance_type can only be t3.micro or t3.small"
  }

  validation {
    condition     = startswith(var.compute.availability_zone, "us-east-1")
    error_message = "availability zone must starts with `us-east-1`"
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

locals {
  effective_compute = {
    name              = var.compute.name
    instance_type     = var.compute.instance_type
    availability_zone = var.compute.availability_zone
    tags = merge({
      Name      = var.compute.name
      Challenge = "84"
      },
      var.compute.tags,
    )
    user_data_is_null = var.compute.user_data == null
  }
}

output "compute_contract" {
  value = {
    name              = local.effective_compute.name
    instance_type     = local.effective_compute.instance_type
    availability_zone = local.effective_compute.availability_zone
    tags              = local.effective_compute.tags
    user_data_is_null = local.effective_compute.user_data_is_null

    instance_id = aws_instance.exercise.id
    ami_id      = aws_instance.exercise.ami
    subnet_id   = aws_instance.exercise.subnet_id
  }
}
