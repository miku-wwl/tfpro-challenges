locals {
  # TODO: expand fleet capacity into stable, two-digit replica identities.
  replicas = {}
}

data "aws_subnet" "selected" { id = var.subnet_id }

resource "aws_launch_template" "replica" {
  for_each = local.replicas

  name          = "${var.run_id}-${replace(replace(each.key, "@", "-"), "#", "-")}"
  image_id      = var.image_id
  instance_type = each.value.fleet.instance_type
  user_data = base64encode(jsonencode({
    fleet_key       = each.value.fleet_key
    replica_key     = each.key
    release         = each.value.fleet.release
    artifact_sha256 = each.value.fleet.artifact_sha256
    managed_by      = "terraform"
  }))
  iam_instance_profile { name = var.instance_profile_name }
  tag_specifications {
    resource_type = "instance"
    tags = {
      Challenge  = "49", ManagedBy = "terraform", RunId = var.run_id, FleetKey = each.value.fleet_key,
      ReplicaKey = each.key, Location = var.location, Release = each.value.fleet.release, ArtifactDigest = each.value.fleet.artifact_sha256
    }
  }
}

resource "aws_instance" "replica" {
  for_each             = local.replicas
  ami                  = var.image_id
  instance_type        = each.value.fleet.instance_type
  subnet_id            = data.aws_subnet.selected.id
  iam_instance_profile = var.instance_profile_name
  tags = {
    Name       = "${var.run_id}-${each.value.fleet.name}-${var.location}-${format("%02d", each.value.replica)}"
    Challenge  = "49", ManagedBy = "terraform", RunId = var.run_id, FleetKey = each.value.fleet_key,
    ReplicaKey = each.key, Location = var.location, Release = each.value.fleet.release, ArtifactDigest = each.value.fleet.artifact_sha256
  }
  lifecycle { replace_triggered_by = [aws_launch_template.replica[each.key]] }
}
