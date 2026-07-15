locals {
  profiles = merge(
    { for key, module in module.service_primary : key => module.profile },
    { for key, module in module.service_dr : key => module.profile },
  )
}
output "deployment_keys" { value = sort(keys(local.profiles)) }
output "deployment_addresses" {
  value = sort(concat(
    [for key in sort(keys(module.service_primary)) : "module.service_primary[\"${key}\"].aws_s3_object.service"],
    [for key in sort(keys(module.service_dr)) : "module.service_dr[\"${key}\"].aws_s3_object.service"],
  ))
}
output "deployments_by_owner" {
  value = { for owner in toset([for profile in values(local.profiles) : profile.owner]) : owner => sort([for key, profile in local.profiles : key if profile.owner == owner]) }
}
output "contract_sha256" { value = sha256(jsonencode({ keys = sort(keys(local.profiles)), owners = { for key, profile in local.profiles : key => profile.owner } })) }
