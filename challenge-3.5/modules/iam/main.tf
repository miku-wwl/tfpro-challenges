terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.80.0"
    }
  }
}

resource "aws_iam_user" "lb" {
  name = var.iam_user_name
}

resource "aws_iam_user_policy" "lb_ro" {
  name = var.iam_user_policy_name
  user = aws_iam_user.lb.name

  policy = var.policy
}