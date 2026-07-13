output "regional_inventory" {
  value = {
    primary = module.platform.primary
    # TODO: 不能让 DR output 指向 primary。
    dr = module.platform.primary
  }
}

output "failover_dependency" {
  value = module.platform.failover_dependency
}

