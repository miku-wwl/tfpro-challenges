output "replica_keys" { value = sort(keys(local.replicas)) }
output "contract" {
  value = {
    location         = var.location
    region           = var.region
    subnet_id        = data.aws_subnet.selected.id
    vpc_id           = data.aws_subnet.selected.vpc_id
    image_id         = var.image_id
    launch_templates = { for key, item in aws_launch_template.replica : key => item.id }
    instances        = { for key, item in aws_instance.replica : key => item.id }
  }
}
