output "replica_ids" {
  value = {
    for key, instance in aws_instance.replica : key => instance.id
  }
}

output "runtime_contracts" {
  value = {
    for fleet_key, fleet in var.fleets : fleet_key => {
      role               = var.role
      region             = var.region
      artifact_name      = fleet.artifact
      artifact_key       = var.release_contract.artifacts[fleet.artifact].key
      artifact_digest    = var.release_contract.artifacts[fleet.artifact].sha256
      release_version    = var.release_contract.release_version
      launch_template_id = aws_launch_template.fleet[fleet_key].id
      instance_ids = [
        for replica_key, instance in aws_instance.replica : instance.id
        if startswith(replica_key, "${fleet_key}#")
      ]
    }
  }
}
