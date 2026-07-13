resource "aws_s3_bucket" "artifact" {
  for_each      = var.deployments
  bucket        = "${var.run_id}-${replace(each.key, "@", "-")}"
  force_destroy = true

  tags = {
    Service = each.value.name
    Owner   = each.value.owner
    Role    = var.role
    Managed = "terraform"
  }
}

resource "aws_s3_object" "manifest" {
  for_each = var.deployments
  bucket   = aws_s3_bucket.artifact[each.key].id
  key      = "contracts/manifest.json"
  content = jsonencode({
    deployment_key = each.key
    port           = each.value.port
    network        = var.network_contract
    platform       = var.platform_contract
  })
  content_type = "application/json"
}
