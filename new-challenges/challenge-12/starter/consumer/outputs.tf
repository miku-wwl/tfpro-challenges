output "deployment_manifest" {
  value = {
    for name, resource in terraform_data.application : name => resource.output
  }
}
