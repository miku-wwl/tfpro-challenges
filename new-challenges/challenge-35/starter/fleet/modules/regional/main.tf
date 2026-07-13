locals {
  tags = { ManagedBy = "terraform", RunId = var.run_id, Lab = "challenge-35", Role = var.role }
  # TODO: 应按 desired_capacity 展开稳定的 name@location#NN replica map。
  replicas = var.fleets
}
resource "aws_launch_template" "fleet" {
  for_each      = var.fleets
  name          = "${var.run_id}-${each.key}-lt"
  image_id      = var.ami_id
  instance_type = each.value.instance_type
  tags          = merge(local.tags, { Fleet = each.key })
}
resource "aws_instance" "replica" {
  for_each               = local.replicas
  ami                    = var.ami_id
  instance_type          = each.value.instance_type
  subnet_id              = var.subnet_id
  vpc_security_group_ids = [var.security_group_id]
  iam_instance_profile   = var.instance_profile_name
  tags                   = merge(local.tags, { Name = "${var.run_id}-${each.key}", Fleet = each.key })
}
