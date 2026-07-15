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
  name_groups = { for artifact in local.artifact_rows : artifact.name => artifact... }
  key_groups  = { for artifact in local.artifact_rows : artifact.key => artifact... }
  catalog_valid = (
    try(toset(keys(local.raw_catalog)) == toset(["artifacts", "revision", "schema_version"]), false) &&
    try(local.raw_catalog.schema_version == 1, false) &&
    try(can(regex("^v[1-9][0-9]*$", local.raw_catalog.revision)), false) &&
    length(local.artifact_rows) == 2 &&
    alltrue([for artifact in local.artifact_rows :
      toset(artifact.fields) == toset(["content", "key", "name", "owner"]) &&
      can(regex("^[a-z0-9][a-z0-9-]{1,30}$", artifact.name)) &&
      can(regex("^releases/[a-z0-9][a-z0-9._/-]{1,100}$", artifact.key)) &&
      !strcontains(artifact.key, "..") && length(artifact.content) > 0 &&
      can(regex("^[a-z0-9][a-z0-9-]{1,30}$", artifact.owner))
    ]) &&
    alltrue([for _, group in local.name_groups : length(group) == 1]) &&
    alltrue([for _, group in local.key_groups : length(group) == 1])
  )
  # TODO: publish a stable name-keyed map only after the strict catalog contract succeeds.
  artifacts_by_name = {}
  contract_artifacts = {
    for name, artifact in local.artifacts_by_name : name => {
      key            = artifact.key
      arn            = "${aws_s3_bucket.artifacts.arn}/${artifact.key}"
      owner          = artifact.owner
      content_sha256 = sha256(artifact.content)
    }
  }
}

resource "aws_s3_bucket" "artifacts" {
  bucket        = "tfpro-c48-artifacts-${var.run_id}"
  force_destroy = true
  tags = {
    Challenge = "48"
    ManagedBy = "terraform"
    Role      = "foundation"
    RunId     = var.run_id
  }
  lifecycle {
    precondition {
      condition     = local.catalog_valid
      error_message = "The artifact catalog violates the strict publication contract."
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
  tags = {
    Artifact  = each.key
    Challenge = "48"
    ManagedBy = "terraform"
    Revision  = local.raw_catalog.revision
    RunId     = var.run_id
  }
}
