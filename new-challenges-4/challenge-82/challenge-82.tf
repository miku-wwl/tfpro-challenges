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
    autoscaling = "http://localhost:4566"
    ec2         = "http://localhost:4566"
    sts         = "http://localhost:4566"
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
    values = ["us-east-1a"]
  }

  filter {
    name   = "default-for-az"
    values = ["true"]
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
  name                   = var.resource_name
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

  lifecycle {
    ignore_changes = [tag_specifications]
  }
}

resource "aws_autoscaling_group" "release" {
  name                      = var.resource_name
  min_size                  = 1
  desired_capacity          = 1
  max_size                  = 2
  vpc_zone_identifier       = [data.aws_subnet.selected.id]
  health_check_type         = "EC2"
  health_check_grace_period = 300
  wait_for_capacity_timeout = "2m"

  launch_template {
    id      = aws_launch_template.release.id
    version = tostring(aws_launch_template.release.latest_version)
  }

  tag {
    key                 = "Challenge"
    value               = "82"
    propagate_at_launch = true
  }

  tag {
    key                 = "ManagedBy"
    value               = "Terraform"
    propagate_at_launch = true
  }
}

output "launch_template_contract" {
  value = {
    id              = aws_launch_template.release.id
    name            = aws_launch_template.release.name
    image_id        = data.aws_ami.selected.id
    default_version = aws_launch_template.release.default_version
    latest_version  = aws_launch_template.release.latest_version
    block_devices = [
      for device_name in sort(keys(local.block_devices)) :
      local.block_devices[device_name]
    ]
    autoscaling_group = {
      arn              = aws_autoscaling_group.release.arn
      name             = aws_autoscaling_group.release.name
      min_size         = aws_autoscaling_group.release.min_size
      desired_capacity = aws_autoscaling_group.release.desired_capacity
      max_size         = aws_autoscaling_group.release.max_size
      subnet_ids       = aws_autoscaling_group.release.vpc_zone_identifier
    }
  }
}
