data "aws_caller_identity" "current" {
  provider = aws.workload
}

resource "aws_s3_bucket" "artifact" {
  provider      = aws.workload
  for_each      = var.applications
  bucket        = "tfpro-c28-${var.run_id}-${each.value.name}-${var.location}"
  force_destroy = true
  tags          = { Challenge = "28", ManagedBy = "terraform", RunId = var.run_id, Owner = each.value.owner, Location = var.location }
}

resource "aws_s3_object" "receipt" {
  provider = aws.workload
  for_each = var.applications

  bucket = aws_s3_bucket.artifact[each.key].id
  key    = "platform/receipt.json"
  # TODO: publish canonical platform/application contract with etag and source_hash.
}
