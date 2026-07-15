output "service_names" { value = sort(keys(local.services)) }
output "bucket_name" { value = aws_s3_bucket.inventory.bucket }
output "index_key" { value = aws_s3_object.index.key }
output "inventory_sha256" { value = sha256(jsonencode(local.canonical_inventory)) }
output "managed_addresses" {
  value = concat(
    ["aws_s3_bucket.inventory", "aws_s3_object.index"],
    [for name in sort(keys(local.services)) : "aws_s3_object.service[\"${name}\"]"],
  )
}
