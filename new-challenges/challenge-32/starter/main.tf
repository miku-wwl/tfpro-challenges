locals {
  # TODO: 收紧为 ssm:GetParameter 与 ssm:GetParameters。
  permission_actions = ["ssm:*"]

  rendered_user_data = templatefile(var.user_data_template_path, {
    api_token          = var.bootstrap.api_token
    database_password  = var.bootstrap.database_password
    feature_flags_json = jsonencode(var.bootstrap.feature_flags)
  })
}

# TODO: 用 check 拒绝空集合、wildcard 与 tfpro namespace 之外的 parameter ARN。

data "aws_caller_identity" "current" {}

data "aws_ami" "selected" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-*-amd64-server-*"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

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

data "aws_iam_policy_document" "permissions" {
  statement {
    sid       = "ReadExplicitBootstrapParameters"
    effect    = "Allow"
    actions   = local.permission_actions
    resources = ["*"] # TODO: 只能引用显式 allowed_parameter_arns。
  }
}

resource "aws_iam_role" "workload" {
  name               = "${var.name_prefix}-workload"
  path               = var.identity_boundary.role_path
  assume_role_policy = data.aws_iam_policy_document.trust.json

  tags = {
    ManagedBy = "terraform"
    RunId     = var.run_id
  }
}

resource "aws_iam_policy" "bootstrap_read" {
  name        = "${var.name_prefix}-bootstrap-read"
  path        = var.identity_boundary.role_path
  description = "Read only explicitly approved bootstrap parameters"
  policy      = data.aws_iam_policy_document.permissions.json

  tags = {
    ManagedBy = "terraform"
    RunId     = var.run_id
  }
}

resource "aws_iam_role_policy_attachment" "bootstrap_read" {
  role       = aws_iam_role.workload.name
  policy_arn = aws_iam_policy.bootstrap_read.arn
}

resource "aws_iam_instance_profile" "workload" {
  name = "${var.name_prefix}-workload"
  path = var.identity_boundary.role_path
  role = aws_iam_role.workload.name

  tags = {
    ManagedBy = "terraform"
    RunId     = var.run_id
  }
}

resource "aws_launch_template" "identity" {
  name          = "${var.name_prefix}-identity"
  image_id      = data.aws_ami.selected.id
  instance_type = "t3.micro"
  user_data     = base64encode(local.rendered_user_data)

  iam_instance_profile {
    name = aws_iam_instance_profile.workload.name
  }

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name      = "${var.name_prefix}-workload"
      ManagedBy = "terraform"
      RunId     = var.run_id
    }
  }

  tags = {
    Name      = "${var.name_prefix}-identity"
    ManagedBy = "terraform"
    RunId     = var.run_id
  }

  # TODO: 窄范围处理 LocalStack 对 launch-template tag specification 的回读差异。
}
