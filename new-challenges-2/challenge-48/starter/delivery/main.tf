data "terraform_remote_state" "foundation" {
  backend = "s3"
  config = {
    bucket                      = var.state_bucket
    key                         = var.foundation_state_key
    region                      = var.aws_region
    access_key                  = "test"
    secret_key                  = "test"
    use_path_style              = true
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_requesting_account_id  = true
    endpoints                   = { s3 = var.localstack_endpoint }
  }
}

locals {
  contract     = try(data.terraform_remote_state.foundation.outputs.artifact_contract, {})
  raw_manifest = try(jsondecode(file("${path.module}/${var.manifest_path}")), {})
  grant_rows = try([
    for grant in local.raw_manifest.grants : {
      id       = lower(trimspace(try(grant.id, "")))
      artifact = lower(trimspace(try(grant.artifact, "")))
      fields   = sort(keys(grant))
    }
  ], [])
  id_groups = { for grant in local.grant_rows : grant.id => grant... }
  manifest_valid = (
    try(toset(keys(local.raw_manifest)) == toset(["grants", "schema_version"]), false) &&
    try(local.raw_manifest.schema_version == 1, false) && length(local.grant_rows) > 0 &&
    alltrue([for grant in local.grant_rows :
      toset(grant.fields) == toset(["artifact", "id"]) &&
      can(regex("^[a-z0-9][a-z0-9-]{1,30}$", grant.id)) &&
      contains(try(keys(local.contract.artifacts), []), grant.artifact)
    ]) &&
    alltrue([for _, group in local.id_groups : length(group) == 1])
  )
  contract_valid = (
    try(local.contract.contract_version == 1, false) &&
    try(local.contract.producer_run_id == var.run_id, false) &&
    try(local.contract.revision == var.expected_revision, false) &&
    try(can(regex("^arn:aws:s3:::tfpro-c48-artifacts-", local.contract.bucket_arn)), false) &&
    try(toset(keys(local.contract.artifacts)) == toset(["api", "worker"]), false)
  )
  aggregate_valid = local.manifest_valid && local.contract_valid
  # TODO: compile the validated remote contract and grant manifest into stable IAM statements.
  grants_by_id = {}
  common_tags = {
    Challenge = "48"
    ManagedBy = "terraform"
    Revision  = try(local.contract.revision, "invalid")
    RunId     = var.run_id
  }
}

data "aws_iam_policy_document" "trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "access" {
  dynamic "statement" {
    for_each = local.grants_by_id
    content {
      sid       = "Read${replace(title(statement.key), "-", "")}"
      effect    = "Allow"
      actions   = ["s3:GetObject"]
      resources = [local.contract.artifacts[statement.value.artifact].arn]
    }
  }
}

resource "aws_iam_role" "consumer" {
  name               = "tfpro-c48-${var.run_id}"
  assume_role_policy = data.aws_iam_policy_document.trust.json
  tags               = local.common_tags
  lifecycle {
    precondition {
      condition     = local.aggregate_valid
      error_message = "The remote artifact contract or IAM grant manifest is invalid."
    }
  }
}

resource "aws_iam_policy" "consumer" {
  name   = "tfpro-c48-${var.run_id}"
  policy = data.aws_iam_policy_document.access.json
  tags   = local.common_tags
}

resource "aws_iam_role_policy_attachment" "consumer" {
  role       = aws_iam_role.consumer.name
  policy_arn = aws_iam_policy.consumer.arn
}
