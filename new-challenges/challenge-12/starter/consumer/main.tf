data "terraform_remote_state" "producer" {
  backend = "s3"

  # TODO 4: configure the LocalStack S3 backend from variables using test/test credentials and skip flags.
  config = {}
}

locals {
  # TODO 5: consume only the producer's release_contract output.
  release_contract = {
    schema_version = 0
    environment    = "unknown"
    bucket_name    = "unknown"
    object_keys    = {}
  }
}

resource "aws_s3_bucket" "receipts" {
  bucket        = "${var.name_prefix}-consumer"
  force_destroy = true
  tags          = { ManagedBy = "terraform", Challenge = "12", Role = "consumer" }
}

resource "aws_s3_object" "receipt" {
  # TODO 6: key instances by the producer's stable service map.
  for_each = {}

  bucket       = aws_s3_bucket.receipts.id
  key          = "receipts/${each.key}.json"
  content      = jsonencode({ service = each.key, source_bucket = local.release_contract.bucket_name, source_key = each.value })
  content_type = "application/json"
  etag         = md5(jsonencode({ service = each.key, source_bucket = local.release_contract.bucket_name, source_key = each.value }))

  lifecycle {
    precondition {
      condition     = local.release_contract.schema_version == 1
      error_message = "The consumer requires release contract schema version 1."
    }
  }
}
