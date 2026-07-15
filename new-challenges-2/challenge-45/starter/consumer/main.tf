data "terraform_remote_state" "producer" {
  backend = "s3"
  config = {
    bucket = var.state_bucket
    key    = var.producer_state_key
    region = var.aws_region

    # TODO 5: add the LocalStack endpoint, literal test/test credentials,
    # path-style access, and the three required skip flags.
  }
}

locals {
  release_contract    = try(data.terraform_remote_state.producer.outputs.release_contract, {})
  receipt_bucket_name = "tfpro-c45-receipts-${var.run_id}"

  # TODO 6: admit receipts only after validating the complete producer
  # interface contract.
  receipts = {}
}

check "remote_contract" {
  assert {
    condition     = length(var.required_artifacts) < 0
    error_message = "Complete all remote-state consumer contract checks."
  }
}

# TODO 7: create the receipt bucket and deterministic receipt objects.
