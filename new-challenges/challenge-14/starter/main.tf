module "release" {
  source = "../fixtures/modules/release-v2"

  service_name     = var.service_name
  release_channels = var.release_channels
}

resource "terraform_data" "contract" {
  input = module.release.manifest

  lifecycle {
    precondition {
      condition     = module.release.manifest.schema_version == 2
      error_message = "The release manifest must use schema version 2."
    }

    postcondition {
      condition = (
        self.output.schema_version == 2 &&
        toset(keys(self.output.artifacts)) == var.release_channels
      )
      error_message = "The artifact set must match release_channels."
    }
  }
}
