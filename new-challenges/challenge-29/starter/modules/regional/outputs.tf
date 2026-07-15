output "contracts" {
  value = {
    for key in sort(keys(var.services)) : key => {
      region      = var.region
      bucket      = "${var.run_id}-${key}-${var.role}"
      role_name   = "${var.run_id}-${key}-${var.role}"
      policy_name = "${var.run_id}-${key}-${var.role}-artifact"
      peer_bucket = lookup(var.peer_buckets, key, null)
    }
  }
}
