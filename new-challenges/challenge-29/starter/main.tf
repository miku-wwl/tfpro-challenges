locals {
  rows = csvdecode(file("${path.module}/${var.catalog_file}"))
  services = {
    # TODO: Row index is not stable identity; filter environment and enabled rows.
    for index, row in local.rows : tostring(index) => {
      name           = trimspace(row.name)
      owner          = trimspace(row.owner)
      environment    = trimspace(row.environment)
      retention_days = tonumber(row.retention_days)
      enabled        = tobool(row.enabled)
    }
  }
}

module "replication" {
  source = "./modules/replication"
  providers = {
    aws.primary = aws.primary
    # TODO: DR is incorrectly routed to primary.
    aws.dr = aws.primary
  }
  run_id   = var.run_id
  services = local.services
}

