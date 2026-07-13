# TODO: 输出 workspace、稳定服务 key、bucket/topic 名称及 owner 合同。
output "release_contract" {
  value = {
    workspace   = "TODO"
    services    = []
    buckets     = {}
    topics      = {}
    topic_names = {}
    owners      = {}
    workspace_tags = {
      buckets = {}
      topics  = {}
    }
  }
}
