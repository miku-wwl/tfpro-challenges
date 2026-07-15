output "consumer_guard" {
  value = local.contract_valid
  precondition {
    condition     = local.contract_valid
    error_message = "promotion contract invalid."
  }
}
# TODO: output active region, address, generation, run id, and instance id.
