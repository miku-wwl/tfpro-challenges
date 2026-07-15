output "release_contract" {
  description = "Runtime 唯一允许消费的版本化发布合同。"
  # TODO 4: 发布 contract_version=1、release_version、bucket、region，以及按 artifact name 索引的 key/digest。
  value = {
    contract_version = 0
    release_version  = try(local.manifest.release_version, "")
    bucket_name      = aws_s3_bucket.release.id
    region           = var.aws_region
    artifacts        = {}
  }
}

output "object_ids" {
  value = {
    for name, object in aws_s3_object.artifact : name => object.id
  }
}
