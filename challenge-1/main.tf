terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.80.0"
    }
  }
}

provider "aws" {
  region                      = var.region
  access_key                  = "test"
  secret_key                  = "test"
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true
  s3_use_path_style           = true

  endpoints {
    s3  = var.localstack_endpoint
    iam = var.localstack_endpoint
    ec2 = var.localstack_endpoint
    sts = var.localstack_endpoint
  }

  default_tags {
    tags = {
      Environment = var.environement
    }
  }
}
resource "random_pet" "this" {}

resource "aws_iam_user" "lb" {
  count = 3
  name  = "${random_pet.this.id}-${var.org-name}-${count.index}"
}

output "user_names" {
  value = aws_iam_user.lb.*.name
}

# This policy must be associated with all IAM users created through this code.

resource "aws_iam_user_policy" "lb_ro" {
  count = 3
  name  = "ec2-describe-policy"
  user  = aws_iam_user.lb[count.index].name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "ec2:Describe*",
        ]
        Effect   = "Allow"
        Resource = "*"
      },
    ]
  })
}



resource "aws_s3_bucket" "example" {
  for_each = toset(var.s3_buckets)
  bucket   = "${random_pet.this.id}-${each.value}"
}

output "s3_buckets" {
  value = [for bucket in aws_s3_bucket.example : bucket.id]
}

resource "aws_s3_object" "object" {
  for_each = toset(var.s3_buckets)
  bucket   = aws_s3_bucket.example[each.key].id
  key      = var.s3_base_object
}

# resource "aws_security_group" "example" {
#   name = var.sg_name
# }

# output "sg_id" {
#   # value = aws_security_group.example.name
#   value = aws_security_group.example.id
# }

# resource "aws_vpc_security_group_ingress_rule" "example" {
#   security_group_id = aws_security_group.example.id

#   cidr_ipv4   = "10.0.0.0/8"
#   from_port   = 80
#   ip_protocol = "tcp"
#   to_port     = 80
# }

# output "sg_rule_id" {
#   value = aws_vpc_security_group_ingress_rule.example.id
# }