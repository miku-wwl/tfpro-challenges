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

resource "aws_launch_template" "release" {
  name                   = "tfpro-c82-release"
  image_id               = data.aws_ami.selected.id
  instance_type          = "t3.micro"
  update_default_version = true

  block_device_mappings {
    device_name = "/dev/sda1"

    ebs {
      delete_on_termination = "true"
      encrypted             = "true"
      iops                  = 3000
      throughput            = 125
      volume_size           = 8
      volume_type           = "gp3"
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

# Tasks 2-5 replace the literal block above with a validated catalog and a
# dynamic block_device_mappings block, then add a second volume.
