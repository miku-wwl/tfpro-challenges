locals {
  manifest_file = abspath("${path.root}/${var.manifest_path}")
  manifest_dir  = dirname(local.manifest_file)
  manifest      = jsondecode(file(local.manifest_file))
  artifact_rows = [for row in try(local.manifest.artifacts, []) : {
    name        = trimspace(try(row.name, ""))
    key         = trimspace(try(row.key, ""))
    source      = trimspace(try(row.source, ""))
    source_path = abspath("${local.manifest_dir}/${trimspace(try(row.source, ""))}")
    sha256      = lower(trimspace(try(row.sha256, "")))
    fields      = sort(keys(row))
  }]

  # TODO: 行号不是稳定制品身份；应先分组检查重复，再以 name 建图。
  artifacts = { for index, artifact in local.artifact_rows : tostring(index) => artifact }
}

resource "aws_s3_bucket" "release" {
  bucket        = "${var.run_id}-release-artifacts"
  force_destroy = true
  tags          = { Name = "${var.run_id}-release-artifacts", RunId = var.run_id, Lab = "challenge-40", ManagedBy = "terraform" }
}
resource "aws_s3_object" "artifact" {
  for_each     = local.artifacts
  bucket       = aws_s3_bucket.release.id
  key          = each.value.key
  source       = each.value.source_path
  etag         = filemd5(each.value.source_path)
  content_type = "text/plain"
  # TODO: 完整发布 digest/release/name/run 标签。
  tags = { RunId = var.run_id }
}
