output "deployment_contract" {
  value = {
    revision           = try(local.contract.revision, null)
    source_fingerprint = try(local.contract.fingerprint, null)
    node_keys          = sort(keys(local.nodes_by_name))
    image_id           = data.aws_ami.selected.id
    subnet_id          = data.aws_subnet.selected.id
    vpc_id             = data.aws_subnet.selected.vpc_id
    security_group_id  = aws_security_group.runtime.id
    launch_templates   = { for name, template in aws_launch_template.node : name => template.id }
    instances          = { for name, instance in aws_instance.node : name => instance.id }
    artifact_digests   = {} # TODO: expose the exact node-to-artifact digest contract.
  }
}
