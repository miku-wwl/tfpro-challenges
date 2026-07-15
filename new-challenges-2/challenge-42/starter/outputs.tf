output "route_keys" { value = sort(keys(local.routes)) }
output "routing_contract" { value = module.routed_storage.routing_contract }
output "managed_contract" { value = module.routed_storage.managed_contract }
output "address_contract" {
  value = sort([
    "module.routed_storage.aws_iam_role.audit",
    "module.routed_storage.aws_iam_role.dr",
    "module.routed_storage.aws_iam_role.primary",
    "module.routed_storage.aws_s3_bucket.audit",
    "module.routed_storage.aws_s3_bucket.dr",
    "module.routed_storage.aws_s3_bucket.primary",
  ])
}
