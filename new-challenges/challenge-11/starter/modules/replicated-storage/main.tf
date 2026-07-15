data "aws_caller_identity" "primary" {
  provider = aws.primary
}

data "aws_caller_identity" "recovery" {
  # TODO 3: bind the recovery caller lookup to aws.recovery.
}

resource "aws_s3_bucket" "primary" {
  provider      = aws.primary
  bucket        = "${var.name_prefix}-primary"
  force_destroy = true
  tags          = merge(var.common_tags, { role = "primary", region = var.primary_region })
}

resource "aws_s3_bucket" "recovery" {
  # TODO 4: bind the recovery bucket to aws.recovery.
  bucket        = "${var.name_prefix}-recovery"
  force_destroy = true
  tags          = merge(var.common_tags, { role = "recovery", region = var.recovery_region })
}

