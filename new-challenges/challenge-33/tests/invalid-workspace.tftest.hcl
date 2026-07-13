mock_provider "aws" {}

run "invalid_cli_workspace_is_rejected" {
  command = plan

  variables {
    name_prefix  = "mock-c33"
    run_id       = "unit"
    catalog_file = "fixtures/services.csv"
  }

  expect_failures = [terraform_data.catalog_guard]
}
