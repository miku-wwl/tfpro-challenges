data "aws_subnet" "selected" {
  id = var.subnet_id
}

resource "aws_instance" "node" {
  for_each             = var.fleets
  ami                  = var.image_id
  instance_type        = each.value.instance_type
  subnet_id            = data.aws_subnet.selected.id
  iam_instance_profile = var.instance_profile_name
  # TODO: make a remote release change replace, rather than mutate, each runtime.
  user_data_replace_on_change = false
  user_data = jsonencode({
    release         = var.platform_contract.release_version
    artifact_arn    = var.platform_contract.artifact.arn
    artifact_sha256 = var.platform_contract.artifact.sha256
    fleet_key       = each.key
    managed_by      = "terraform"
  })

  tags = {
    Name           = "${var.run_id}-${each.value.name}-${var.location}"
    Challenge      = "50"
    ManagedBy      = "terraform"
    RunId          = var.run_id
    FleetKey       = each.key
    Location       = var.location
    Release        = var.platform_contract.release_version
    ArtifactDigest = var.platform_contract.artifact.sha256
  }
}
