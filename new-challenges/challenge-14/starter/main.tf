# This is the old baseline. Upgrade it to the release-v2 source and interface.
module "release" {
  source = "../fixtures/modules/release-v1"

  name     = var.service_name
  channels = sort(tolist(var.release_channels))
}

resource "terraform_data" "contract" {
  # TODO: consume module.release.manifest and enforce schema v2 with lifecycle
  # precondition/postcondition assertions.
  input = module.release.legacy_release
}
