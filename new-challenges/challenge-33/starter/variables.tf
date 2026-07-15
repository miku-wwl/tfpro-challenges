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
    condition = (
      can(regex("^https?://(localhost|127\\.0\\.0\\.1|\\[::1\\]):([1-9][0-9]{0,4})\\z", var.localstack_endpoint)) &&
      try(tonumber(regex("^https?://(localhost|127\\.0\\.0\\.1|\\[::1\\]):([1-9][0-9]{0,4})\\z", var.localstack_endpoint)[1]) <= 65535, false)
    )
    error_message = "localstack_endpoint 必须是带显式有效端口的 loopback HTTP(S) 根地址。"
  }
}

variable "name_prefix" {
  type        = string
  description = "资源名前缀。"
  default     = "tfpro-c33"
}

variable "run_id" {
  type        = string
  description = "并发验收隔离标识。"
  default     = "lab"
}

variable "environment" {
  type        = string
  description = "显式发布环境；backend key 由 grader 独立注入。"
  default     = "dev"

  # TODO: 只允许 dev、stage、prod。
}

variable "catalog_file" {
  type        = string
  description = "服务 CSV 路径。"
  default     = "fixtures/services.csv"
}
