data "aws_iam_policy_document" "trust" {
  statement {
    sid     = "Ec2AssumeRole"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

data "aws_subnet" "primary" { id = var.primary_subnet_id }
data "aws_ami" "primary" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = [var.ami_pattern]
  }
}

data "aws_subnet" "dr" {
  provider = aws.dr
  id       = var.dr_subnet_id
}

data "aws_ami" "dr" {
  provider    = aws.dr
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = [var.ami_pattern]
  }
}

locals {
  tags = {
    ManagedBy = "terraform"
    Ownership = "regional-migration"
    RunId     = var.run_id
  }
}

resource "aws_iam_role" "legacy" {
  name               = "${var.run_id}-role"
  assume_role_policy = data.aws_iam_policy_document.trust.json
  tags               = merge(local.tags, { Name = "${var.run_id}-role", RegionRole = "shared" })
}

resource "aws_iam_instance_profile" "legacy" {
  name = "${var.run_id}-profile"
  role = aws_iam_role.legacy.name
  tags = merge(local.tags, { Name = "${var.run_id}-profile", RegionRole = "shared" })
}

resource "aws_security_group" "primary" {
  name        = "${var.run_id}-primary"
  description = "primary launch security group"
  vpc_id      = data.aws_subnet.primary.vpc_id
  tags        = merge(local.tags, { Name = "${var.run_id}-primary", RegionKey = "primary" })
}

resource "aws_launch_template" "primary" {
  name                   = "${var.run_id}-primary"
  image_id               = data.aws_ami.primary.id
  instance_type          = "t3.micro"
  vpc_security_group_ids = [aws_security_group.primary.id]
  user_data              = base64encode("#!/bin/sh\necho primary\n")
  iam_instance_profile { name = aws_iam_instance_profile.legacy.name }
}

resource "aws_security_group" "dr" {
  provider    = aws.dr
  name        = "${var.run_id}-dr"
  description = "dr launch security group"
  vpc_id      = data.aws_subnet.dr.vpc_id
  tags        = merge(local.tags, { Name = "${var.run_id}-dr", RegionKey = "dr" })
}

resource "aws_launch_template" "dr" {
  provider               = aws.dr
  name                   = "${var.run_id}-dr"
  image_id               = data.aws_ami.dr.id
  instance_type          = "t3.small"
  vpc_security_group_ids = [aws_security_group.dr.id]
  user_data              = base64encode("#!/bin/sh\necho dr\n")
  iam_instance_profile { name = aws_iam_instance_profile.legacy.name }
}

output "primary_security_group_id" { value = aws_security_group.primary.id }
output "dr_security_group_id" { value = aws_security_group.dr.id }
