data "aws_region" "primary" {
  provider = aws.primary
}

data "aws_region" "recovery" {
  # TODO: 显式绑定 recovery slot。
}

data "aws_caller_identity" "primary" {
  provider = aws.primary
}

data "aws_caller_identity" "recovery" {
  # TODO: 显式绑定 recovery slot。
}

resource "aws_s3_bucket" "primary" {
  provider = aws.primary
  bucket   = "${var.name_prefix}-primary"
  tags     = merge(var.common_tags, { role = "primary" })
}

resource "aws_s3_bucket" "recovery" {
  # TODO: 显式绑定 recovery slot。
  bucket = "${var.name_prefix}-recovery"
  tags   = merge(var.common_tags, { role = "recovery" })
}

