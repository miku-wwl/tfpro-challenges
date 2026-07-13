variable "name_prefix" {
  type        = string
  description = "唯一的小写资源名前缀。"
  default     = "tfpro-c20"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{2,32}$", var.name_prefix))
    error_message = "name_prefix 必须是 3–33 位小写字母、数字或连字符。"
  }
}

variable "primary_region" {
  type        = string
  description = "主区域。"
  default     = "us-east-1"
}

variable "dr_region" {
  type        = string
  description = "灾备区域。"
  default     = "us-west-2"

  validation {
    condition     = var.dr_region != var.primary_region
    error_message = "dr_region 必须与 primary_region 不同。"
  }
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

