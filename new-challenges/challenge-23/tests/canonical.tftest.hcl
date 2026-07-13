mock_provider "aws" {}

run "v2_interface_is_named_and_versioned" {
  command = plan

  variables {
    name_prefix         = "mock-c23"
    localstack_endpoint = "http://localhost:4566"
  }

  assert {
    condition     = output.network_v2.schema_version == 2
    error_message = "network_v2.schema_version 必须为 2。"
  }

  assert {
    condition     = toset(keys(output.network_v2.subnets)) == toset(["app-a", "app-b"])
    error_message = "subnets 必须用 app-a/app-b 业务名称索引。"
  }

  assert {
    condition     = toset(keys(output.network_v2.security_groups)) == toset(["app", "ops"])
    error_message = "security_groups 必须用 app/ops 业务名称索引。"
  }
}
