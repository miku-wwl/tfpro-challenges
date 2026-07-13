resource "aws_s3_bucket" "primary" {
  provider      = aws.primary
  bucket        = "${var.name_prefix}-primary"
  force_destroy = true

  tags = {
    ManagedBy = "terraform"
    Role      = "primary"
  }
}

resource "aws_sns_topic" "primary_events" {
  provider = aws.primary
  name     = "${var.name_prefix}-primary-events"

  tags = {
    ManagedBy = "terraform"
    Role      = "primary"
  }
}

resource "aws_s3_bucket" "dr" {
  provider      = aws.dr
  bucket        = "${var.name_prefix}-dr"
  force_destroy = true

  tags = {
    ManagedBy = "terraform"
    Role      = "dr"
  }
}

resource "aws_sns_topic" "dr_events" {
  provider = aws.dr
  name     = "${var.name_prefix}-dr-events"

  tags = {
    ManagedBy = "terraform"
    Role      = "dr"
  }
}

