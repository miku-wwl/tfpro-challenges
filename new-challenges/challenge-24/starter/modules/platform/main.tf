# TODO: 为每个 slot 使用对应 provider；当前所有读取和资源都错误地走 primary。
data "aws_caller_identity" "primary" { provider = aws.primary }
data "aws_caller_identity" "dr" { provider = aws.primary }
data "aws_caller_identity" "audit" { provider = aws.primary }

data "aws_region" "primary" { provider = aws.primary }
data "aws_region" "dr" { provider = aws.primary }
data "aws_region" "audit" { provider = aws.primary }

resource "aws_s3_bucket" "primary" {
  provider      = aws.primary
  bucket        = var.primary_bucket_name
  force_destroy = true
}

resource "aws_s3_bucket" "dr" {
  provider      = aws.primary
  bucket        = var.dr_bucket_name
  force_destroy = true
}

resource "aws_iam_role" "audit" {
  provider = aws.primary
  name     = var.audit_role_name
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_policy" "audit" {
  provider = aws.primary
  name     = "${var.audit_role_name}-policy"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:GetObject", "s3:ListBucket"]
      Resource = [aws_s3_bucket.primary.arn, "${aws_s3_bucket.primary.arn}/*"]
    }]
  })
}

resource "aws_iam_role_policy_attachment" "audit" {
  provider   = aws.primary
  role       = aws_iam_role.audit.name
  policy_arn = aws_iam_policy.audit.arn
}

check "localstack_test_account" {
  assert {
    condition = alltrue([
      data.aws_caller_identity.primary.account_id == var.expected_account_id,
      data.aws_caller_identity.dr.account_id == var.expected_account_id,
      data.aws_caller_identity.audit.account_id == var.expected_account_id,
    ])
    error_message = "provider slot 没有连接到预期 LocalStack 测试账号。"
  }
}
