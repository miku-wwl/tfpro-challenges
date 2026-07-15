output "contract" {
  value = {
    location  = var.location
    region    = var.region
    subnet_id = data.aws_subnet.selected.id
    vpc_id    = data.aws_subnet.selected.vpc_id
    image_id  = var.image_id
    instances = { for key, instance in aws_instance.node : key => instance.id }
  }
}
