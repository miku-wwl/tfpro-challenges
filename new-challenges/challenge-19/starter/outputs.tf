output "adoption_contract" {
  value = {
    bucket_name = local.bucket_name
    table_name  = local.table_name
    manifest    = local.manifest_key
  }
}

output "canonical_addresses" {
  value = [
    "aws_s3_bucket.archive",
    "aws_dynamodb_table.locks",
    "aws_s3_object.release_manifest",
    "terraform_data.inventory",
  ]
}
