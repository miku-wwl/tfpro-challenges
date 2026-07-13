resource "terraform_data" "contract" {
  input = {
    schema_version = 2
    environment    = var.environment
    release_id     = var.release_id
    services       = sort(tolist(var.services))
  }
}
