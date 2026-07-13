run "v2_module_contract" {
  command = plan

  assert {
    condition = output.service_ports == {
      api    = 8080
      web    = 3000
      worker = 9090
    }
    error_message = "模块重构改变了服务端口。"
  }

  assert {
    condition     = alltrue([for version in values(output.module_contract_versions) : version == 2])
    error_message = "所有 child module 都必须实现 v2 contract。"
  }

  assert {
    condition     = output.healthcheck_paths.api == "/ready"
    error_message = "v2 contract 必须透传 api healthcheck。"
  }

  assert {
    condition     = output.healthcheck_paths.web == null && output.healthcheck_paths.worker == null
    error_message = "未提供的 optional healthcheck 必须保持 null。"
  }

  assert {
    condition     = jsonencode(output.resource_addresses) == jsonencode(["module.service[\"api\"].terraform_data.this", "module.service[\"web\"].terraform_data.this", "module.service[\"worker\"].terraform_data.this"])
    error_message = "最终地址必须使用稳定的具名 module key。"
  }
}
