module "primary" {
  source       = "../regional"
  providers    = { aws.workload = aws.primary }
  run_id       = var.run_id
  role         = "primary"
  region       = var.primary_region
  services     = var.services
  peer_buckets = {}
}

module "dr" {
  source = "../regional"

  # TODO: Route aws.dr and pass the keyed primary bucket contract.
  providers    = { aws.workload = aws.primary }
  run_id       = var.run_id
  role         = "dr"
  region       = var.dr_region
  services     = var.services
  peer_buckets = {}
}
