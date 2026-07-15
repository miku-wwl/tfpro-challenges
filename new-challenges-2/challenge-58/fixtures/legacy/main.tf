locals {
  identities = [
    { name = "api", owner = "platform", actions = ["s3:GetObject"] },
    { name = "worker", owner = "delivery", actions = ["s3:GetObject"] },
  ]
}

data "aws_iam_policy_document" "trust" {
  statement {
    sid     = "TrustCompute"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "access" {
  count = length(local.identities)

  statement {
    sid       = "ReadArtifacts"
    effect    = "Allow"
    actions   = local.identities[count.index].actions
    resources = ["arn:aws:s3:::tfpro-c58-artifacts/${local.identities[count.index].name}/*"]
  }
}

resource "aws_iam_role" "legacy" {
  count = length(local.identities)

  name                  = "${var.run_id}-${local.identities[count.index].name}-role"
  description           = "Imported identity role for ${local.identities[count.index].name}"
  assume_role_policy    = data.aws_iam_policy_document.trust.json
  force_detach_policies = false
  tags = {
    Challenge = "58"
    Identity  = local.identities[count.index].name
    ManagedBy = "terraform"
    Name      = "${var.run_id}-${local.identities[count.index].name}-role"
    Owner     = local.identities[count.index].owner
    RunId     = var.run_id
  }
}

resource "aws_iam_policy" "legacy" {
  count = length(local.identities)

  name        = "${var.run_id}-${local.identities[count.index].name}-policy"
  description = "Imported artifact policy for ${local.identities[count.index].name}"
  policy      = data.aws_iam_policy_document.access[count.index].json
  tags = {
    Challenge = "58"
    Identity  = local.identities[count.index].name
    ManagedBy = "terraform"
    Name      = "${var.run_id}-${local.identities[count.index].name}-policy"
    Owner     = local.identities[count.index].owner
    RunId     = var.run_id
  }
}

resource "aws_iam_role_policy_attachment" "legacy" {
  count = length(local.identities)

  role       = aws_iam_role.legacy[count.index].name
  policy_arn = aws_iam_policy.legacy[count.index].arn
}
