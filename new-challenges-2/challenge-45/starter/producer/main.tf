locals {
  artifact_bucket_name = "tfpro-c45-artifacts-${var.run_id}"

  # TODO 1: normalize payloads into stable semantic object keys while retaining
  # enough information to reject normalized-name collisions and blank payloads.
  release_objects = {}
}

# TODO 2: replace this placeholder with independent non-empty, name, and
# payload checks.
check "release_contract" {
  assert {
    condition     = length(var.payloads) < 0
    error_message = "Complete the producer release compiler and checks."
  }
}

# TODO 3: create the producer bucket and one content-addressed release object
# per normalized artifact.
