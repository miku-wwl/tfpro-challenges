output "backend_contract" {
  value = {
    bucket         = var.state_bucket_name
    dynamodb_table = var.lock_table_name
    region         = var.aws_region
  }
}
