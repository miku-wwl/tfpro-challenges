locals {
  manifest_file = abspath("${path.root}/${var.manifest_path}")
  manifest_dir  = dirname(local.manifest_file)
  manifest      = jsondecode(file(local.manifest_file))

  artifact_rows = [
    for row in try(local.manifest.artifacts, []) : {
      name        = trimspace(try(row.name, ""))
      key         = trimspace(try(row.key, ""))
      source      = trimspace(try(row.source, ""))
      source_path = abspath("${local.manifest_dir}/${trimspace(try(row.source, ""))}")
      sha256      = lower(trimspace(try(row.sha256, "")))
    }
  ]

  # TODO 1: 用 artifact.name 建立稳定 for_each 身份，并在构造 map 前保留重复检测能力。
  artifacts = {
    for index, artifact in local.artifact_rows : tostring(index) => artifact
  }
}

resource "terraform_data" "manifest_guard" {
  input = length(local.artifact_rows)

  lifecycle {
    # TODO 2: 用 6 个独立 guards 分别验证 schema、contract version、release version、
    # 数量+唯一性、字段+路径+digest 格式，以及 payload 的真实 digest；不得合并或填空壳。
    precondition {
      condition     = length(local.artifact_rows) >= 0
      error_message = "Complete the manifest contract guard."
    }
  }
}

resource "aws_s3_bucket" "release" {
  bucket        = "${var.run_id}-release-artifacts"
  force_destroy = true

  tags = {
    Name      = "${var.run_id}-release-artifacts"
    RunId     = var.run_id
    Lab       = "challenge-40"
    ManagedBy = "terraform"
  }
}

resource "aws_s3_object" "artifact" {
  for_each = local.artifacts

  bucket       = aws_s3_bucket.release.id
  key          = each.value.key
  source       = each.value.source_path
  etag         = filemd5(each.value.source_path)
  content_type = "text/plain"

  # TODO 3: 给对象加入 ArtifactName、ArtifactDigest、ReleaseVersion、RunId 发布标签。
  tags = {
    RunId = var.run_id
  }

  depends_on = [terraform_data.manifest_guard]
}
