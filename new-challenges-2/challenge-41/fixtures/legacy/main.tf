locals {
  services = [
    { name = "api", owner = "platform", enabled = true },
    { name = "worker", owner = "operations", enabled = true },
  ]
}

data "aws_iam_policy_document" "assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_s3_bucket" "release" {
  count         = length(local.services)
  bucket        = "${var.run_id}-${local.services[count.index].name}-release"
  force_destroy = true
  tags = {
    Lab       = "challenge-41"
    ManagedBy = "terraform"
    Name      = "${var.run_id}-${local.services[count.index].name}"
    Owner     = local.services[count.index].owner
    RunId     = var.run_id
    Service   = local.services[count.index].name
  }
}

resource "aws_s3_object" "manifest" {
  count        = length(local.services)
  bucket       = aws_s3_bucket.release[count.index].id
  key          = "release/manifest.json"
  content      = jsonencode({ owner = local.services[count.index].owner, service = local.services[count.index].name })
  content_type = "application/json"
  etag         = md5(jsonencode({ owner = local.services[count.index].owner, service = local.services[count.index].name }))
  tags = {
    Lab       = "challenge-41"
    ManagedBy = "terraform"
    Name      = "${var.run_id}-${local.services[count.index].name}"
    Owner     = local.services[count.index].owner
    RunId     = var.run_id
    Service   = local.services[count.index].name
  }
}

resource "aws_iam_role" "publisher" {
  count              = length(local.services)
  name               = "${var.run_id}-${local.services[count.index].name}-publisher"
  assume_role_policy = data.aws_iam_policy_document.assume.json
  tags = {
    Lab       = "challenge-41"
    ManagedBy = "terraform"
    Name      = "${var.run_id}-${local.services[count.index].name}"
    Owner     = local.services[count.index].owner
    RunId     = var.run_id
    Service   = local.services[count.index].name
  }
}
