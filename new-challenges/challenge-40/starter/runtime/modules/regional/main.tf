locals {
  replicas = merge([
    for fleet_key, fleet in var.fleets : {
      for index in range(fleet.replicas) :
      "${fleet_key}#${format("%02d", index + 1)}" => {
        fleet_key      = fleet_key
        replica_number = index + 1
        fleet          = fleet
        artifact       = var.release_contract.artifacts[fleet.artifact]
      }
    }
  ]...)
}

resource "aws_security_group" "runtime" {
  name        = "${var.run_id}-${var.role}-runtime"
  description = "Challenge 40 ${var.role} release runtime"
  vpc_id      = var.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name      = "${var.run_id}-${var.role}-runtime"
    RunId     = var.run_id
    Role      = var.role
    Lab       = "challenge-40"
    ManagedBy = "terraform"
  }
}

resource "aws_launch_template" "fleet" {
  for_each = var.fleets

  name                   = "${var.run_id}-${var.role}-${each.value.name}"
  image_id               = var.ami_id
  instance_type          = each.value.instance_type
  vpc_security_group_ids = [aws_security_group.runtime.id]

  # TODO 9: user_data 必须注入 contract/release、bucket、artifact name/key/digest。
  user_data = base64encode(jsonencode({
    bucket_name   = var.release_contract.bucket_name
    artifact_name = each.value.artifact
  }))

  iam_instance_profile {
    name = var.instance_profile_name
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      RunId = var.run_id
    }
  }

  tags = {
    Name      = "${var.run_id}-${var.role}-${each.value.name}"
    RunId     = var.run_id
    Role      = var.role
    Lab       = "challenge-40"
    ManagedBy = "terraform"
  }

  lifecycle {
    ignore_changes = [tag_specifications]
  }
}

resource "terraform_data" "release_revision" {
  for_each = local.replicas

  # TODO 10: 版本、digest 和 LT latest_version 都必须参与受控替换哨兵。
  triggers_replace = {
    template_id = aws_launch_template.fleet[each.value.fleet_key].id
  }
}

resource "aws_instance" "replica" {
  for_each = local.replicas

  subnet_id = var.subnet_id
  launch_template {
    id      = aws_launch_template.fleet[each.value.fleet_key].id
    version = "$Latest"
  }

  # TODO 11: 加入稳定身份、区域和完整 release/artifact 追踪标签。
  tags = {
    Name  = "${var.run_id}-${each.key}"
    RunId = var.run_id
  }

  lifecycle {
    ignore_changes       = [launch_template]
    replace_triggered_by = [terraform_data.release_revision[each.key]]
  }
}
