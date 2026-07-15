bucket         = "tfpro-c22-state-<unique-run-id>"
key            = "producer/terraform.tfstate"
region         = "us-east-1"
dynamodb_table = "tfpro-c22-lock-<unique-run-id>"
access_key     = "test"
secret_key     = "test"
use_path_style = true

skip_credentials_validation = true
skip_metadata_api_check     = true
skip_requesting_account_id  = true

endpoints = {
  s3       = "http://localhost:4566"
  dynamodb = "http://localhost:4566"
}
