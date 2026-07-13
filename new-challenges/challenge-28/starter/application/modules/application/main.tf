resource "aws_s3_bucket" "artifact" {
  bucket        = "${var.run_id}-${replace(var.deployment_key, "@", "-")}"
  force_destroy = true
  tags = {
    Application = var.application.name
    Owner       = var.application.owner
    Region      = var.network.region
  }
}

resource "aws_sns_topic" "events" {
  name = "${var.run_id}-${replace(var.deployment_key, "@", "-")}-events"
  tags = {
    Application = var.application.name
    Port        = tostring(var.application.port)
  }
}

