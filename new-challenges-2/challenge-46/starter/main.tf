data "aws_caller_identity" "current" {}

locals {
  raw_catalog = try(jsondecode(file("${path.module}/${var.catalog_path}")), {})
  catalog_rows = try([
    for artifact in local.raw_catalog.artifacts : {
      name    = lower(trimspace(try(artifact.name, "")))
      key     = trimspace(try(artifact.key, ""))
      content = try(artifact.content, "")
      owner   = lower(trimspace(try(artifact.owner, "")))
      fields  = sort(keys(artifact))
    }
  ], [])

  name_groups = { for artifact in local.catalog_rows : artifact.name => artifact... }
  key_groups  = { for artifact in local.catalog_rows : artifact.key => artifact... }
  schema_valid = (
    try(toset(keys(local.raw_catalog)) == toset(["artifacts", "release", "schema_version"]), false) &&
    try(local.raw_catalog.schema_version == 1, false) &&
    try(can(regex("^v[1-9][0-9]*$", local.raw_catalog.release)), false) &&
    length(local.catalog_rows) > 0 &&
    alltrue([for artifact in local.catalog_rows : toset(artifact.fields) == toset(["content", "key", "name", "owner"])])
  )
  values_valid = alltrue([
    for artifact in local.catalog_rows :
    can(regex("^[a-z0-9][a-z0-9-]{1,30}$", artifact.name)) &&
    can(regex("^releases/[a-z0-9][a-z0-9._/-]{1,100}$", artifact.key)) &&
    !strcontains(artifact.key, "..") && !startswith(artifact.key, "/") &&
    length(artifact.content) > 0 && length(artifact.content) <= 4096 &&
    can(regex("^[a-z0-9][a-z0-9-]{1,30}$", artifact.owner))
  ])
  identities_unique = (
    alltrue([for _, group in local.name_groups : length(group) == 1]) &&
    alltrue([for _, group in local.key_groups : length(group) == 1])
  )
  # TODO: combine the independent schema, value, and identity checks.
  catalog_valid = false
  # TODO: build the stable name-keyed publication map only for a valid catalog.
  artifacts_by_name = {}

  # TODO: derive the order-independent artifact contract and its canonical fingerprint.
  semantic_artifacts   = {}
  semantic_fingerprint = ""
}

resource "aws_s3_bucket" "artifacts" {
  bucket        = "tfpro-c46-${var.run_id}"
  force_destroy = true

  tags = {
    Challenge = "46"
    RunId     = var.run_id
    ManagedBy = "terraform"
    Purpose   = "release-artifacts"
  }

  lifecycle {
    precondition {
      condition     = local.catalog_valid
      error_message = "The release catalog violates the required schema or safety contract."
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
    Challenge = "46"
    ManagedBy = "terraform"
    Release   = local.raw_catalog.release
    RunId     = var.run_id
  }
}
