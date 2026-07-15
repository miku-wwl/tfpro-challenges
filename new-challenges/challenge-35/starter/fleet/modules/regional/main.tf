locals {
  tags = { ManagedBy = "terraform", RunId = var.run_id, Lab = "challenge-35", Role = var.role }
}

resource "aws_launch_template" "fleet" {
  for_each               = var.fleets
  name                   = "${var.run_id}-${each.value.name}-${var.role}"
  image_id               = var.ami_id
  instance_type          = each.value.instance_type
  vpc_security_group_ids = [var.network.security_group_id]
}

resource "aws_instance" "fleet" {
  for_each               = var.fleets
  ami                    = var.ami_id
  instance_type          = each.value.instance_type
  subnet_id              = var.network.subnet_id
  vpc_security_group_ids = [var.network.security_group_id]
  iam_instance_profile   = var.instance_profile
  tags = merge(local.tags, {
    Name             = "${var.run_id}-${each.value.name}-${var.role}"
    Fleet            = each.key
    Owner            = each.value.owner
    LaunchTemplateId = aws_launch_template.fleet[each.key].id
  })
}
