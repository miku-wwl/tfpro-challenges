output "release_manifest" {
  # TODO: expose the checked v2 manifest.
  value = terraform_data.contract.output
}
