output "contract" {
  value = {
    route       = var.route
    region      = var.region
    account_id  = data.aws_caller_identity.current.account_id
    ami_id      = data.aws_ami.selected.id
    subnet_id   = data.aws_subnet.selected.id
    vpc_id      = data.aws_subnet.selected.vpc_id
    instance_id = aws_instance.node.id
    tags        = aws_instance.node.tags
  }
}
