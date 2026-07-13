run "producer_contract_is_stable" {
  command = apply

  variables {
    release_id = "mock-release"
    services   = ["worker", "api"]
  }

  assert {
    condition     = output.platform_contract.schema_version == 2
    error_message = "producer contract schema 必须为 2。"
  }

  assert {
    condition     = output.platform_contract.services[0] == "api" && output.platform_contract.services[1] == "worker"
    error_message = "producer services 必须稳定排序。"
  }

  assert {
    condition     = output.platform_contract.release_id == "mock-release"
    error_message = "release_id 没有进入 producer 合同。"
  }
}
