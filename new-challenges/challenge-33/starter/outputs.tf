# TODO: 输出 environment、稳定服务 key、bucket/object 合同及 owner 合同。
output "catalog_guard" {
  value = false
  # TODO: 用 precondition 阻断任何非法目录。
}

output "release_contract" {
  value = {
    environment  = "TODO"
    services     = []
    buckets      = {}
    objects      = {}
    object_etags = {}
    owners       = {}
    environment_tags = {
      buckets = {}
      objects = {}
    }
  }
}
