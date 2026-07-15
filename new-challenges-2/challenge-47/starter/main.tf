locals {
  raw_catalog = try(jsondecode(file("${path.module}/${var.catalog_path}")), {})
  route_rows = try([
    for route in local.raw_catalog.routes : {
      name   = lower(trimspace(try(route.name, "")))
      owner  = lower(trimspace(try(route.owner, "")))
      fields = sort(keys(route))
    }
  ], [])
  route_groups = { for route in local.route_rows : route.name => route... }
  catalog_valid = (
    try(toset(keys(local.raw_catalog)) == toset(["routes", "schema_version"]), false) &&
    try(local.raw_catalog.schema_version == 1, false) &&
    length(local.route_rows) == 2 &&
    toset(keys(local.route_groups)) == toset(["audit", "primary"]) &&
    alltrue([for route in local.route_rows :
      toset(route.fields) == toset(["name", "owner"]) &&
      can(regex("^[a-z0-9][a-z0-9-]{1,30}$", route.owner))
    ]) &&
    alltrue([for _, group in local.route_groups : length(group) == 1])
  )
  # TODO: compile the validated rows into a stable route-name map.
  routes_by_name = {}
  common_tags = {
    Challenge = "47"
    ManagedBy = "terraform"
    RunId     = var.run_id
  }
  routing_valid = (
    local.catalog_valid && var.primary_region != var.audit_region &&
    var.primary_subnet_id != var.audit_subnet_id
  )
}

data "aws_iam_policy_document" "ec2_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "workload" {
  name               = "tfpro-c47-${var.run_id}"
  assume_role_policy = data.aws_iam_policy_document.ec2_trust.json
  tags               = local.common_tags

  lifecycle {
    precondition {
      condition     = local.routing_valid
      error_message = "The route catalog, distinct regions, and distinct injected subnets are mandatory."
    }
  }
}

resource "aws_iam_instance_profile" "workload" {
  name = "tfpro-c47-${var.run_id}"
  role = aws_iam_role.workload.name
  tags = local.common_tags
}

module "primary" {
  source    = "./modules/regional"
  providers = { aws = aws }

  route                = "primary"
  region               = var.primary_region
  run_id               = var.run_id
  image_name           = "tfpro-c47-${var.run_id}-primary"
  subnet_id            = var.primary_subnet_id
  instance_type        = var.instance_type
  iam_instance_profile = aws_iam_instance_profile.workload.name
  owner                = try(local.routes_by_name.primary.owner, "invalid")
  common_tags          = local.common_tags
}

module "audit" {
  source = "./modules/regional"
  # TODO: route this module through the aliased audit provider.
  providers = { aws = aws }

  route                = "audit"
  region               = var.audit_region
  run_id               = var.run_id
  image_name           = "tfpro-c47-${var.run_id}-audit"
  subnet_id            = var.audit_subnet_id
  instance_type        = var.instance_type
  iam_instance_profile = aws_iam_instance_profile.workload.name
  owner                = try(local.routes_by_name.audit.owner, "invalid")
  common_tags          = local.common_tags
}
