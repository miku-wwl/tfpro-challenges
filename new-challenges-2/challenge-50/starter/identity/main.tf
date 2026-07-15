locals {
  common_tags = {
    Challenge = "50"
    ManagedBy = "terraform"
    RunId     = var.run_id
    State     = "identity"
  }
  # TODO: build the least-privilege release-object policy published by this state.
  runtime_policy = {
    Version   = "2012-10-17"
    Statement = []
  }
}

resource "aws_iam_role" "runtime" {
  name = "tfpro-c50-${var.run_id}"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Principal = { Service = "ec2.amazonaws.com" }, Action = "sts:AssumeRole" }]
  })
  tags = local.common_tags

  lifecycle {
    precondition {
      condition     = var.contract_version == 1
      error_message = "identity contract_version must be 1."
    }
  }
}

resource "aws_iam_policy" "runtime" {
  name   = "tfpro-c50-${var.run_id}"
  policy = jsonencode(local.runtime_policy)
  tags   = local.common_tags
}

resource "aws_iam_role_policy_attachment" "runtime" {
  role       = aws_iam_role.runtime.name
  policy_arn = aws_iam_policy.runtime.arn
}

resource "aws_iam_instance_profile" "runtime" {
  name = "tfpro-c50-${var.run_id}"
  role = aws_iam_role.runtime.name
  tags = local.common_tags
}
