output "consumer_guard" {
  value = local.contract_valid
  precondition {
    condition     = local.contract_valid
    error_message = "foundation contract invalid."
  }
}
# TODO: output every scalar regional contract field and recomputable contract_id.
