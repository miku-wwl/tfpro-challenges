mock_provider "aws" {}

run "backend_bootstrap_contract" {
  command = plan

  variables {
    state_bucket_name = "mock-c22-state"
    lock_table_name   = "mock-c22-locks"
  }

  assert {
    condition     = output.backend_contract.bucket == "mock-c22-state"
    error_message = "bootstrap 必须原样发布 state bucket 名称。"
  }

  assert {
    condition     = output.backend_contract.dynamodb_table == "mock-c22-locks"
    error_message = "bootstrap 必须原样发布 lock table 名称。"
  }

  assert {
    condition     = aws_dynamodb_table.locks.hash_key == "LockID"
    error_message = "DynamoDB backend lock key 必须是 LockID。"
  }
}
