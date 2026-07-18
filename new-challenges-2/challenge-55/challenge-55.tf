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

variable "desired_capacity" {
  description = "Desired capacity managed by the real Auto Scaling Group."
  type        = number
  default     = 1

  validation {
    condition     = var.desired_capacity >= 1 && var.desired_capacity <= 4
    error_message = "desired_capacity must be between 1 and 4."
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

resource "aws_security_group" "fleet" {
  name        = "tfpro-c55-fleet"
  description = "Challenge 55 rule-model comparison"
  vpc_id      = data.aws_subnet.selected.vpc_id

  tags = {
    Challenge = "55"
  }
}

resource "aws_security_group_rule" "legacy_ssh" {
  type              = "ingress"
  security_group_id = aws_security_group.fleet.id
  protocol          = "tcp"
  from_port         = 22
  to_port           = 22
  cidr_blocks       = ["10.55.0.0/16"]
  description       = "legacy-resource-model"
}

resource "aws_launch_template" "fleet" {
  name_prefix            = "tfpro-c55-"
  image_id               = data.aws_ami.selected.id
  instance_type          = "t3.micro"
  vpc_security_group_ids = [aws_security_group.fleet.id]

  tag_specifications {
    resource_type = "instance"
    tags = {
      Challenge = "55"
      Fleet     = "tfpro-c55-fleet"
    }
  }
}

resource "aws_autoscaling_group" "fleet" {
  name                      = "tfpro-c55-fleet"
  min_size                  = 1
  max_size                  = 4
  desired_capacity          = var.desired_capacity
  vpc_zone_identifier       = [data.aws_subnet.selected.id]
  health_check_type         = "EC2"
  health_check_grace_period = 300
  wait_for_capacity_timeout = "2m"

  launch_template {
    id      = aws_launch_template.fleet.id
    version = tostring(aws_launch_template.fleet.latest_version)
  }

  tag {
    key                 = "Challenge"
    value               = "55"
    propagate_at_launch = true
  }

  tag {
    key                 = "Fleet"
    value               = "tfpro-c55-fleet"
    propagate_at_launch = true
  }
}

output "fleet_contract" {
  value = {
    autoscaling_group  = aws_autoscaling_group.fleet.name
    min_size           = aws_autoscaling_group.fleet.min_size
    desired_capacity   = aws_autoscaling_group.fleet.desired_capacity
    max_size           = aws_autoscaling_group.fleet.max_size
    launch_template_id = aws_launch_template.fleet.id
    security_group_id  = aws_security_group.fleet.id
    subnet_id          = data.aws_subnet.selected.id
  }
}
