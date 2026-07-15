output "instance_ids" { value = { for key, instance in aws_instance.fleet : key => instance.id } }
output "runtime_contracts" {
  value = { for key, fleet in var.fleets : key => {
    role               = var.role
    region             = var.region
    artifact_name      = fleet.artifact
    artifact_key       = try(var.release_contract.artifacts[fleet.artifact].key, "")
    artifact_digest    = try(var.release_contract.artifacts[fleet.artifact].sha256, "")
    release_version    = try(var.release_contract.release_version, "")
    launch_template_id = aws_launch_template.fleet[key].id
    instance_id        = aws_instance.fleet[key].id
    subnet_id          = var.subnet_id
    security_group_id  = aws_security_group.runtime.id
  } }
}
