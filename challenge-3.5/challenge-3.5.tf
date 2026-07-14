terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.80.0"
    }
    local = {
      source = "hashicorp/local"
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
    iam = "http://localhost:4566"
    sts = "http://localhost:4566"
  }
}

# Task 1: move this resource to modules/compute.
resource "aws_launch_template" "this" {
  name          = "terraform-launch-template"
  image_id      = "ami-00000000000000000"
  instance_type = "t2.micro"
}

# LocalStack Community does not include Auto Scaling. This resource represents
# ASG desired capacity for the lifecycle/ignore_changes exercise in Task 5.
resource "terraform_data" "desired_capacity" {
  input = 1
}

# Task 1: move these resources to modules/iam.
resource "aws_iam_user" "lb" {
  name = "success-user"
}

resource "aws_iam_user_policy" "lb_ro" {
  name = "ec2-describe-policy"
  user = aws_iam_user.lb.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action   = ["ec2:Describe*"]
      Effect   = "Allow"
      Resource = "*"
    }]
  })
}

data "aws_caller_identity" "local" {}

resource "local_file" "this" {
  content  = data.aws_caller_identity.local.account_id
  filename = "account-number.txt"
}
