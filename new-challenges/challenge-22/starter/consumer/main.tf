data "terraform_remote_state" "producer" {
  backend = "s3"

  # TODO 22-C2: complete the Terraform 1.6 LocalStack S3 remote-state configuration.
  config = {
    bucket = var.state_bucket
    key    = var.producer_state_key
    region = var.aws_region
  }
}
locals {
  release_contract    = data.terraform_remote_state.producer.outputs.release_contract
  receipt_bucket_name = "tfpro-c22-receipts-${var.run_id}"

  # TODO 22-C3: derive stable receipt objects only from the published contract.
  receipts = {}
}

resource "terraform_data" "contract_guard" {
  input = local.release_contract

  lifecycle {
    # TODO 22-C4: independently validate schema, producer, release, object set, and digests.
  }
}

resource "aws_s3_bucket" "receipts" {
  bucket        = local.receipt_bucket_name
  force_destroy = true

  tags = {
    Challenge = "22"
    ManagedBy = "terraform"
    RunId     = var.run_id
    Role      = "consumer"
  }
}

# TODO 22-C5: enable versioning before any receipt is published.

resource "aws_s3_object" "receipt" {
  # TODO 22-C6: publish a stable JSON receipt per contract object with source_hash and audit tags.
  bucket  = aws_s3_bucket.receipts.id
  key     = "TODO.json"
  content = "TODO"
}
