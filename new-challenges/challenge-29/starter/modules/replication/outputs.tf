output "regional_contracts" {
  value = {
    primary = module.primary.contracts
    # TODO: Do not cross-reference primary.
    dr = module.primary.contracts
  }
}

