locals {
  common_tags = { ManagedBy = "terraform", RunId = var.run_id, Lab = "challenge-35" }
}

resource "terraform_data" "contract_guard" {
  input = var.run_id
  lifecycle {
    # TODO: 拒绝相同区域与相同 VPC CIDR。
    precondition {
      condition     = length(var.run_id) > 0
      error_message = "Complete the foundation contract guard."
    }
  }
}

resource "aws_vpc" "primary" {
  cidr_block = var.primary_vpc_cidr
  tags       = merge(local.common_tags, { Name = "${var.run_id}-primary-vpc", Role = "primary" })
}
resource "aws_subnet" "primary" {
  vpc_id     = aws_vpc.primary.id
  cidr_block = cidrsubnet(var.primary_vpc_cidr, 8, 1)
  tags       = merge(local.common_tags, { Name = "${var.run_id}-primary-subnet", Role = "primary" })
}
resource "aws_security_group" "primary" {
  name   = "${var.run_id}-primary-compute"
  vpc_id = aws_vpc.primary.id
  tags   = merge(local.common_tags, { Role = "primary" })
}

# TODO: 这三个 DR 资源当前没有明确使用 aws.dr。
resource "aws_vpc" "dr" {
  cidr_block = var.dr_vpc_cidr
  tags       = merge(local.common_tags, { Name = "${var.run_id}-dr-vpc", Role = "dr" })
}
resource "aws_subnet" "dr" {
  vpc_id     = aws_vpc.dr.id
  cidr_block = cidrsubnet(var.dr_vpc_cidr, 8, 1)
  tags       = merge(local.common_tags, { Name = "${var.run_id}-dr-subnet", Role = "dr" })
}
resource "aws_security_group" "dr" {
  name   = "${var.run_id}-dr-compute"
  vpc_id = aws_vpc.dr.id
  tags   = merge(local.common_tags, { Role = "dr" })
}

resource "aws_iam_role" "compute" {
  name = "${var.run_id}-compute-role"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Principal = { Service = "ec2.amazonaws.com" }, Action = "sts:AssumeRole" }]
  })
  tags = local.common_tags
}
resource "aws_iam_instance_profile" "compute" {
  name = "${var.run_id}-compute-profile"
  role = aws_iam_role.compute.name
  tags = local.common_tags
}
