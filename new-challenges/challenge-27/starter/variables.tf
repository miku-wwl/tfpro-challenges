variable "aws_region" {
  type        = string
  description = "LocalStack 使用的 AWS 区域"
  default     = "us-east-1"
}

variable "localstack_endpoint" {
  type        = string
  description = "仅允许 loopback 的 LocalStack edge endpoint"
  default     = "http://localhost:4566"

  validation {
    condition = try(
      tonumber(regex("^https?://(localhost|127\\.0\\.0\\.1|\\[::1\\]):([1-9][0-9]{0,4})\\z", var.localstack_endpoint)[1]) <= 65535,
      false
    )
    error_message = "localstack_endpoint 必须是带 1–65535 显式端口的 loopback HTTP(S) 根地址。"
  }
}

variable "name_prefix" {
  type        = string
  description = "grader 隔离使用的 bucket 前缀"
  default     = "tfpro-c27-lab"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{2,30}$", var.name_prefix))
    error_message = "name_prefix 只能包含小写字母、数字和连字符。"
  }
}

variable "application" {
  type        = string
  description = "manifest 必须匹配的应用名"
  default     = "orders-api"
}

variable "environment" {
  type        = string
  description = "manifest 必须匹配的环境"
  default     = "dev"
}

variable "manifest_path" {
  type        = string
  description = "release manifest JSON 路径"
  default     = "../fixtures/release-v1.json"

  validation {
    condition     = fileexists(var.manifest_path) && can(jsondecode(file(var.manifest_path)))
    error_message = "manifest_path 必须指向可解析的 JSON 文件。"
  }
}
