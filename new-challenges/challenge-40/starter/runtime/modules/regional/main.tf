locals { tags = { RunId = var.run_id, Role = var.role, Lab = "challenge-40", ManagedBy = "terraform" } }

resource "aws_security_group" "runtime" {
  name   = "${var.run_id}-${var.role}-runtime"
  vpc_id = var.vpc_id
  tags   = merge(local.tags, { Name = "${var.run_id}-${var.role}-runtime" })
}
resource "aws_launch_template" "fleet" {
  for_each               = var.fleets
  name                   = "${var.run_id}-${var.role}-${each.value.name}"
  image_id               = var.ami_id
  instance_type          = each.value.instance_type
  vpc_security_group_ids = [aws_security_group.runtime.id]
  user_data = base64encode(jsonencode({
    release_version = try(var.release_contract.release_version, "")
    artifact_key    = try(var.release_contract.artifacts[each.value.artifact].key, "")
  }))
  iam_instance_profile { name = var.instance_profile }
}
resource "aws_instance" "fleet" {
  for_each                    = var.fleets
  ami                         = var.ami_id
  instance_type               = each.value.instance_type
  subnet_id                   = var.subnet_id
  vpc_security_group_ids      = [aws_security_group.runtime.id]
  iam_instance_profile        = var.instance_profile
  user_data_replace_on_change = true
  user_data = jsonencode({
    release_version = try(var.release_contract.release_version, "")
    artifact_key    = try(var.release_contract.artifacts[each.value.artifact].key, "")
  })
  tags = merge(local.tags, {
    Name             = "${var.run_id}-${each.value.name}-${var.role}"
    Fleet            = each.key
    ReleaseVersion   = try(var.release_contract.release_version, "")
    ArtifactDigest   = try(var.release_contract.artifacts[each.value.artifact].sha256, "")
    LaunchTemplateId = aws_launch_template.fleet[each.key].id
  })

  lifecycle {
    create_before_destroy = true
  }
}
