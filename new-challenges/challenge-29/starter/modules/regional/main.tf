data "aws_iam_policy_document" "assume_role" {
  provider = aws.workload

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::000000000000:root"]
    }
  }
}

data "aws_iam_policy_document" "artifact_access" {
  provider = aws.workload
  for_each = var.services

  statement {
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
    ]
    resources = ["arn:aws:s3:::${var.run_id}-${each.key}-${var.role}/*"]
  }
}

resource "aws_s3_bucket" "artifact" {
  provider      = aws.workload
  for_each      = var.services
  bucket        = "${var.run_id}-${each.key}-${var.role}"
  force_destroy = true
  tags = merge(
    {
      Challenge = "29"
      ManagedBy = "terraform"
      RunId     = var.run_id
      Service   = each.key
      Owner     = each.value.owner
      Role      = var.role
    },
    contains(keys(var.peer_buckets), each.key) ? { PeerBucket = var.peer_buckets[each.key] } : {},
  )
}

resource "aws_iam_role" "workload" {
  provider = aws.workload
  for_each = var.services

  name                 = "${var.run_id}-${each.key}-${var.role}"
  assume_role_policy   = data.aws_iam_policy_document.assume_role.json
  max_session_duration = 3600

  tags = {
    Challenge = "29"
    ManagedBy = "terraform"
    RunId     = var.run_id
    Service   = each.key
    Owner     = each.value.owner
    Role      = var.role
  }
}

resource "aws_iam_policy" "artifact" {
  provider = aws.workload
  for_each = var.services

  name   = "${var.run_id}-${each.key}-${var.role}-artifact"
  policy = data.aws_iam_policy_document.artifact_access[each.key].json

  tags = {
    Challenge = "29"
    ManagedBy = "terraform"
    RunId     = var.run_id
    Service   = each.key
    Role      = var.role
  }
}

resource "aws_iam_role_policy_attachment" "artifact" {
  provider = aws.workload
  for_each = var.services

  role       = aws_iam_role.workload[each.key].name
  policy_arn = aws_iam_policy.artifact[each.key].arn
}
