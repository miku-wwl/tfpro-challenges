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

resource "aws_launch_template" "capacity" {
  name          = "tfpro-c35-launch-template"
  image_id      = data.aws_ami.selected.id
  instance_type = "t3.micro"

  tags = {
    Challenge = "35"
    ManagedBy = "Terraform"
  }

  # LocalStack 会把顶层 Launch Template 标签同时回显为等价的
  # tag_specifications；忽略这个模拟器规范化字段，避免永久伪漂移。
  lifecycle {
    ignore_changes = [tag_specifications]
  }
}

resource "aws_autoscaling_group" "capacity" {
  name                      = "tfpro-c35-capacity"
  min_size                  = var.asg_contract.min_size
  desired_capacity          = var.asg_contract.desired_capacity
  max_size                  = var.asg_contract.max_size
  vpc_zone_identifier       = [data.aws_subnet.selected.id]
  health_check_type         = "EC2"
  health_check_grace_period = 300
  wait_for_capacity_timeout = "2m"

  launch_template {
    id      = aws_launch_template.capacity.id
    version = tostring(aws_launch_template.capacity.latest_version)
  }

  tag {
    key                 = "Name"
    value               = "tfpro-c35-capacity"
    propagate_at_launch = true
  }

  tag {
    key                 = "Challenge"
    value               = "35"
    propagate_at_launch = true
  }

  tag {
    key                 = "ManagedBy"
    value               = "Terraform"
    propagate_at_launch = true
  }
}

output "starter_capacity_contract" {
  value = {
    autoscaling_group = {
      arn  = aws_autoscaling_group.capacity.arn
      name = aws_autoscaling_group.capacity.name
    }
    launch_template = {
      id             = aws_launch_template.capacity.id
      name           = aws_launch_template.capacity.name
      latest_version = aws_launch_template.capacity.latest_version
    }
    subnet_id        = data.aws_subnet.selected.id
    min_size         = aws_autoscaling_group.capacity.min_size
    desired_capacity = aws_autoscaling_group.capacity.desired_capacity
    max_size         = aws_autoscaling_group.capacity.max_size
    runtime          = "aws_autoscaling_group"
  }
}
