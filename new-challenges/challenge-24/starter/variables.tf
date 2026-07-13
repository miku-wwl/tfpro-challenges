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

variable "primary_region" {
  type    = string
  default = "us-east-1"
}

variable "dr_region" {
  type    = string
  default = "us-west-2"
}

variable "audit_region" {
  type    = string
  default = "us-east-2"
}

variable "expected_localstack_account_id" {
  type        = string
  description = "LocalStack 固定测试账号；不得改成真实账号"
  default     = "000000000000"

  validation {
    condition     = var.expected_localstack_account_id == "000000000000"
    error_message = "本题只允许 LocalStack 测试账号 000000000000。"
  }
}

variable "name_prefix" {
  type        = string
  description = "小写唯一前缀；grader 会注入"
  default     = "tfpro-c24"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{2,35}$", var.name_prefix))
    error_message = "name_prefix 只能包含小写字母、数字和连字符。"
  }
}
