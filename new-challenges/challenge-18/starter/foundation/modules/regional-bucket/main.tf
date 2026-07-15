data "aws_caller_identity" "current" {}

resource "aws_s3_bucket" "this" {
  bucket        = var.bucket
  force_destroy = true
  tags          = { ManagedBy = "terraform", Challenge = "18", Role = var.role, Region = var.region }
}
