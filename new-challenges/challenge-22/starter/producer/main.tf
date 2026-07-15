locals {
  artifact_bucket_name = "tfpro-c22-artifacts-${var.run_id}"

  # TODO 22-P2: normalize payloads into a logical-name keyed release map.
  release_objects = {}
}
resource "terraform_data" "catalog_guard" {
  input = local.release_objects

  lifecycle {
    # TODO 22-P3: add independent non-empty, safe-name, and nonblank-payload preconditions.
  }
}

resource "aws_s3_bucket" "artifacts" {
  bucket        = local.artifact_bucket_name
  force_destroy = true

  tags = {
    Challenge = "22"
    ManagedBy = "terraform"
    RunId     = var.run_id
    Role      = "producer"
  }
}

# TODO 22-P4: enable versioning before any release object is published.

resource "aws_s3_object" "release" {
  # TODO 22-P5: publish every normalized release with stable for_each, source_hash, and audit tags.
  bucket  = aws_s3_bucket.artifacts.id
  key     = "TODO.txt"
  content = "TODO"
}
