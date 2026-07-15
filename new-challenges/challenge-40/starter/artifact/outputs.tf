output "manifest_guard" {
  value = true
  precondition {
    # TODO: 拆分并完成 manifest schema/version/unique/field/path/digest guards。
    condition     = length(local.artifact_rows) >= 0
    error_message = "Complete the manifest guards."
  }
}
output "release_contract" {
  # TODO: 发布 contract_version=1、run、release、bucket、region 与 name-keyed artifacts。
  value = {
    contract_version = 0
    run_id           = var.run_id
    release_version  = try(local.manifest.release_version, "")
    bucket_name      = aws_s3_bucket.release.id
    region           = var.aws_region
    artifacts        = {}
  }
}
output "object_ids" { value = { for name, object in aws_s3_object.artifact : name => object.id } }
