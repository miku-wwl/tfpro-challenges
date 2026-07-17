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

locals {
  block_devices = {
    for device_name, device in var.block_devices : device_name => {
      device_name = device_name

      ebs = {
        delete_on_termination = tostring(device.delete_on_termination)
        encrypted             = tostring(device.encrypted)
        iops                  = device.iops
        throughput            = device.throughput
        volume_size           = device.volume_size
        volume_type           = device.volume_type
      }
    }
  }
}

resource "aws_launch_template" "release" {
  name                   = "tfpro-c82-release"
  image_id               = data.aws_ami.selected.id
  instance_type          = "t3.micro"
  update_default_version = true

  dynamic "block_device_mappings" {
    for_each = local.block_devices
    content {
      device_name = block_device_mappings.key
      ebs {
        delete_on_termination = block_device_mappings.value.ebs.delete_on_termination
        encrypted             = block_device_mappings.value.ebs.encrypted
        iops                  = block_device_mappings.value.ebs.iops
        throughput            = block_device_mappings.value.ebs.throughput
        volume_size           = block_device_mappings.value.ebs.volume_size
        volume_type           = block_device_mappings.value.ebs.volume_type
      }
    }
  }

  tags = {
    Challenge = "82"
    ManagedBy = "Terraform"
  }
}

output "starter_launch_template" {
  value = {
    id              = aws_launch_template.release.id
    name            = aws_launch_template.release.name
    default_version = aws_launch_template.release.default_version
    latest_version  = aws_launch_template.release.latest_version
  }
}

output "normalized_block_devices" {
  value = local.block_devices
}

# Tasks 2-5 replace the literal block above with a validated catalog and a
# dynamic block_device_mappings block, then add a second volume.
