output "service_keys" { value = sort(keys(local.services)) }
output "bucket_names" { value = { for key, service in module.service : key => service.bucket_name } }
output "object_keys" { value = { for key, service in module.service : key => service.object_key } }
output "role_arns" { value = { for key, service in module.service : key => service.role_arn } }
output "address_contract" {
  value = sort(flatten([for key in sort(keys(local.services)) : [
    "module.service[\"${key}\"].aws_iam_role.publisher",
    "module.service[\"${key}\"].aws_s3_bucket.release",
    "module.service[\"${key}\"].aws_s3_object.manifest",
  ]]))
}
