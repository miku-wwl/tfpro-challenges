locals {
  primary_bucket_name = "tfpro-c28-${var.run_id}-primary"
  dr_bucket_name      = "tfpro-c28-${var.run_id}-dr"

  # TODO: derive canonical primary/dr JSON manifests from platform_revision.
}

resource "aws_s3_bucket" "primary" {
  provider      = aws.primary
  bucket        = local.primary_bucket_name
  force_destroy = true
  tags          = { Challenge = "28", ManagedBy = "terraform", RunId = var.run_id, Role = "primary" }
}

resource "aws_s3_bucket" "dr" {
  provider      = aws.dr
  bucket        = local.dr_bucket_name
  force_destroy = true
  tags          = { Challenge = "28", ManagedBy = "terraform", RunId = var.run_id, Role = "dr" }
}

# TODO: publish one manifest object in each bucket with explicit provider routing.
