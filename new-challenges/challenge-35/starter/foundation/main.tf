data "aws_subnet" "primary" {
  id = var.primary_subnet_id
}

# TODO: DR data source 必须显式路由到 aws.dr。
data "aws_subnet" "dr" {
  id = var.dr_subnet_id
}

data "aws_iam_policy_document" "ec2_trust" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

locals {
  tags = { ManagedBy = "terraform", RunId = var.run_id, Lab = "challenge-35" }
}

resource "aws_security_group" "primary" {
  name   = "${var.run_id}-primary-compute"
  vpc_id = data.aws_subnet.primary.vpc_id
  tags   = merge(local.tags, { Role = "primary" })
}

# TODO: DR resource 也必须显式路由到 aws.dr。
resource "aws_security_group" "dr" {
  name   = "${var.run_id}-dr-compute"
  vpc_id = data.aws_subnet.dr.vpc_id
  tags   = merge(local.tags, { Role = "dr" })
}

resource "aws_iam_role" "compute" {
  name               = "${var.run_id}-compute-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_trust.json
  tags               = local.tags
}

resource "aws_iam_instance_profile" "compute" {
  name = "${var.run_id}-compute-profile"
  role = aws_iam_role.compute.name
  tags = local.tags
}
