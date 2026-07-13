run "stable_identity_contract" {
  command = plan

  assert {
    condition     = jsonencode(output.service_keys) == jsonencode(["api", "web", "worker"])
    error_message = "服务必须使用稳定的服务名作为 for_each key。"
  }

  assert {
    condition     = jsonencode(output.services_by_owner.platform) == jsonencode(["api", "worker"])
    error_message = "owner 聚合结果不正确。"
  }

  assert {
    condition     = endswith(output.manifest_path, "generated/service-manifest.json")
    error_message = "manifest 必须写入约定路径。"
  }
}
