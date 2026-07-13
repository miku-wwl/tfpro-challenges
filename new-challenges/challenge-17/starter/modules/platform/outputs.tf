output "primary" {
  value = module.primary.inventory
}

output "dr" {
  # TODO: 修复交叉引用。
  value = module.primary.inventory
}

output "failover_dependency" {
  value = {
    primary_topic = module.primary.inventory.topic_arn
    # TODO: 应来自 DR 对 peer topic 的确认。
    dr_peer_topic = null
  }
}

