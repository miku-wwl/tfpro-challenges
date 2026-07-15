locals {
  raw_catalog = try(jsondecode(file("${path.module}/${var.catalog_path}")), {})
  artifact_rows = try([
    for artifact in local.raw_catalog.artifacts : {
      name    = lower(trimspace(try(artifact.name, "")))
      key     = trimspace(try(artifact.key, ""))
      owner   = lower(trimspace(try(artifact.owner, "")))
      content = try(artifact.content, "")
      fields  = sort(keys(artifact))
    }
  ], [])
  name_groups        = { for artifact in local.artifact_rows : artifact.name => artifact... }
  key_groups         = { for artifact in local.artifact_rows : artifact.key => artifact... }
  catalog_valid      = false # TODO: enforce exact top/record shape, semantics, uniqueness, and exact identities.
  artifacts_by_name  = {}    # TODO: derive a stable name-keyed map only after validation succeeds.
  bucket_name        = "tfpro-c59-artifacts-${var.run_id}"
  contract_artifacts = {} # TODO: publish canonical key/ARN/owner/SHA-256 values for both artifacts.
  common_tags = {
    Challenge = "59"
    ManagedBy = "terraform"
    RunId     = var.run_id
    State     = "publisher"
  }
}

resource "aws_s3_bucket" "artifacts" {
  bucket        = local.bucket_name
  force_destroy = true
  tags          = local.common_tags

  lifecycle {
    precondition {
      condition     = local.catalog_valid
      error_message = "The artifact publication catalog is invalid."
    }
  }
}

resource "aws_s3_object" "artifact" {
  for_each = local.artifacts_by_name

  bucket       = aws_s3_bucket.artifacts.id
  key          = each.value.key
  content      = each.value.content
  content_type = "text/plain"
  source_hash  = sha256(each.value.content)
  etag         = md5(each.value.content)
  tags = merge(local.common_tags, {
    Artifact = each.key
    Revision = local.raw_catalog.revision
  })
}
