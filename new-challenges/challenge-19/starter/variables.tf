variable "name_prefix" {
  type        = string
  description = "本次迁移使用的全局唯一小写前缀。"
  default     = "tfpro-c19"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{2,30}$", var.name_prefix))
    error_message = "name_prefix 必须是 3–31 位小写字母、数字或连字符。"
  }
}

variable "aws_region" {
  type        = string
  description = "LocalStack 使用的 AWS 区域。"
  default     = "us-east-1"
}

variable "localstack_endpoint" {
  type        = string
  description = "LocalStack edge endpoint。"
  default     = "http://localhost:4566"

  validation {
    condition     = can(regex("^https?://(localhost|127\\.0\\.0\\.1)(:[0-9]+)?/?$", var.localstack_endpoint))
    error_message = "localstack_endpoint 只能指向 localhost 或 127.0.0.1。"
  }
}

