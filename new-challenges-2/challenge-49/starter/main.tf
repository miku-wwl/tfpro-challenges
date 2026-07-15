locals {
  raw_catalog = try(jsondecode(file(var.catalog_path)), {})
  raw_fleets  = try(local.raw_catalog.fleets, [])
  fleets = try([
    for fleet in local.raw_fleets : {
      name            = lower(trimspace(fleet.name))
      location        = lower(trimspace(fleet.location))
      release         = trimspace(fleet.release)
      capacity        = fleet.capacity
      instance_type   = trimspace(fleet.instance_type)
      artifact_sha256 = lower(trimspace(fleet.artifact_sha256))
      fields          = sort(keys(fleet))
      # TODO: include both normalized name and location in the stable fleet identity.
      fleet_key = lower(trimspace(fleet.name))
    }
  ], [])
  fleet_groups = { for fleet in local.fleets : fleet.fleet_key => fleet... }
  catalog_valid = (
    try(toset(keys(local.raw_catalog)) == toset(["fleets", "schema_version"]), false) &&
    try(local.raw_catalog.schema_version == 1, false) && length(local.fleets) >= 1 && length(local.fleets) <= 6 &&
    alltrue([for fleet in local.fleets :
      toset(fleet.fields) == toset(["artifact_sha256", "capacity", "instance_type", "location", "name", "release"]) &&
      can(regex("^[a-z][a-z0-9-]{2,15}$", fleet.name)) && contains(["primary", "dr"], fleet.location) &&
      can(regex("^[0-9]{4}\\.[0-9]{2}\\.[0-9]+$", fleet.release)) &&
      fleet.capacity >= 1 && fleet.capacity <= 2 && floor(fleet.capacity) == fleet.capacity &&
      contains(["t3.micro", "t3.small"], fleet.instance_type) && can(regex("^[0-9a-f]{64}$", fleet.artifact_sha256))
    ]) &&
    alltrue([for _, group in local.fleet_groups : length(group) == 1]) &&
    contains(keys(local.fleet_groups), "api@primary") && contains(keys(local.fleet_groups), "worker@dr")
  )
  # TODO: compile only a valid catalog into the stable fleet map.
  fleets_by_key  = {}
  primary_fleets = { for key, fleet in local.fleets_by_key : key => fleet if fleet.location == "primary" }
  dr_fleets      = { for key, fleet in local.fleets_by_key : key => fleet if fleet.location == "dr" }
  common_tags    = { Challenge = "49", ManagedBy = "terraform", RunId = var.run_id }
}

resource "aws_iam_role" "runtime" {
  name = "tfpro-c49-${var.run_id}"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Principal = { Service = "ec2.amazonaws.com" }, Action = "sts:AssumeRole" }]
  })
  tags = local.common_tags
  lifecycle {
    precondition {
      condition     = local.catalog_valid && var.primary_region != var.dr_region && var.primary_subnet_id != var.dr_subnet_id
      error_message = "The fleet catalog and dual-region injected subnet contract are invalid."
    }
  }
}

resource "aws_iam_instance_profile" "runtime" {
  name = "tfpro-c49-${var.run_id}"
  role = aws_iam_role.runtime.name
  tags = local.common_tags
}

module "primary" {
  source                = "./modules/regional"
  providers             = { aws = aws }
  fleets                = local.primary_fleets
  location              = "primary"
  region                = var.primary_region
  run_id                = var.run_id
  subnet_id             = var.primary_subnet_id
  image_id              = var.primary_image_id
  instance_profile_name = aws_iam_instance_profile.runtime.name
}

module "dr" {
  source = "./modules/regional"
  # TODO: route the DR module through the aliased provider.
  providers             = { aws = aws }
  fleets                = local.dr_fleets
  location              = "dr"
  region                = var.dr_region
  run_id                = var.run_id
  subnet_id             = var.dr_subnet_id
  image_id              = var.dr_image_id
  instance_profile_name = aws_iam_instance_profile.runtime.name
}
