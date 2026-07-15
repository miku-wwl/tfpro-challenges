locals {
  rows = csvdecode(file("${path.module}/${var.catalog_file}"))

  services = {
    # TODO: use normalized service names as keys and filter target/enabled rows.
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
    # TODO: DR must use the aws.dr provider instance.
    aws.dr = aws.primary
  }

  run_id         = var.run_id
  primary_region = var.primary_region
  dr_region      = var.dr_region
  services       = local.services
}
