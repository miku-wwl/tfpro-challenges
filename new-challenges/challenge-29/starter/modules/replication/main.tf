module "primary" {
  source      = "../regional"
  providers   = { aws.workload = aws.primary }
  run_id      = var.run_id
  role        = "primary"
  services    = var.services
  peer_topics = {}
}

module "dr" {
  source = "../regional"
  # TODO: Route aws.dr and pass primary topic contracts with an explicit dependency.
  providers   = { aws.workload = aws.primary }
  run_id      = var.run_id
  role        = "dr"
  services    = var.services
  peer_topics = {}
}

