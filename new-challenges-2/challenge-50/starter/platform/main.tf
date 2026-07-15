data "terraform_remote_state" "identity" {
  backend = "s3"
  config = {
    bucket                      = var.state_bucket
    key                         = var.identity_state_key
    region                      = var.aws_region
    access_key                  = "test"
    secret_key                  = "test"
    use_path_style              = true
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_requesting_account_id  = true
    endpoints = {
      s3 = var.localstack_endpoint
    }
  }
}

locals {
  identity     = try(data.terraform_remote_state.identity.outputs.identity_contract, {})
  manifest     = try(jsondecode(file("${path.module}/${var.manifest_path}")), {})
  artifact     = try(local.manifest.artifact, {})
  payload_path = "${path.module}/../../fixtures/${try(local.artifact.source, "missing")}"

  identity_valid = try(
    local.identity.contract_version == 1 &&
    local.identity.producer_run_id == var.run_id &&
    local.identity.role_name == "tfpro-c50-${var.run_id}" &&
    can(regex("^tfpro-c50-[a-z0-9-]+$", local.identity.instance_profile_name)) &&
    can(regex("^arn:aws:iam::[0-9]{12}:policy/tfpro-c50-[a-z0-9-]+$", local.identity.policy_arn)) &&
    can(regex("^[0-9a-f]{64}$", local.identity.policy_sha256)),
    false
  )

  manifest_valid = try(
    toset(keys(local.manifest)) == toset(["artifact", "contract_version", "release_version", "schema_version"]) &&
    local.manifest.schema_version == 1 &&
    local.manifest.contract_version == 1 &&
    can(regex("^[0-9]{4}\\.[0-9]{2}\\.[0-9]+$", local.manifest.release_version)) &&
    toset(keys(local.artifact)) == toset(["key", "name", "sha256", "source"]) &&
    local.artifact.name == "bootstrap" &&
    local.artifact.key == "releases/bootstrap.txt" &&
    can(regex("^payloads/bootstrap-v[12]\\.txt$", local.artifact.source)) &&
    filesha256(local.payload_path) == local.artifact.sha256,
    false
  )

  # TODO: gate publication on both the remote identity and local manifest contracts.
  aggregate_valid = false
  common_tags = {
    Challenge = "50"
    ManagedBy = "terraform"
    RunId     = var.run_id
    State     = "platform"
  }
}

resource "aws_s3_bucket" "release" {
  bucket        = "tfpro-c50-release-${var.run_id}"
  force_destroy = true
  tags          = local.common_tags

  lifecycle {
    precondition {
      condition     = local.aggregate_valid
      error_message = "Identity or platform manifest contract is invalid."
    }
  }
}

resource "aws_s3_object" "bootstrap" {
  bucket       = aws_s3_bucket.release.id
  key          = local.artifact.key
  source       = local.payload_path
  source_hash  = filesha256(local.payload_path)
  etag         = filemd5(local.payload_path)
  content_type = "text/plain"

  tags = merge(local.common_tags, {
    Artifact = "bootstrap"
    Release  = local.manifest.release_version
  })
}
