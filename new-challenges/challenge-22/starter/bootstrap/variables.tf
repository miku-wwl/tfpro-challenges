variable "aws_region" {
  type        = string
  description = "LocalStack 使用的 AWS 区域"
  default     = "us-east-1"
}

variable "localstack_endpoint" {
  type        = string
  description = "LocalStack edge endpoint；只允许 loopback"
  default     = "http://localhost:4566"

  validation {
    condition = can(regex(
      "^https?://(localhost|127\\.0\\.0\\.1|\\[::1\\])(:[0-9]+)?/?$",
      var.localstack_endpoint,
    ))
    error_message = "localstack_endpoint 必须指向 loopback。"
  }
}

variable "state_bucket_name" {
  type        = string
  description = "唯一 state bucket 名称"
}

variable "lock_table_name" {
  type        = string
  description = "唯一 DynamoDB lock table 名称"
}
