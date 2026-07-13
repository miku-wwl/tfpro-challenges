variable "primary_region" {
  type    = string
  default = "us-east-1"
}

variable "dr_region" {
  type    = string
  default = "us-west-2"

  # TODO: DR region 必须和 primary_region 不同。
}

variable "localstack_endpoint" {
  type        = string
  description = "LocalStack edge endpoint。"
  default     = "http://localhost:4566"

  validation {
    condition     = can(regex("^http://(localhost|127\\.0\\.0\\.1):[0-9]+$", var.localstack_endpoint))
    error_message = "localstack_endpoint must be a loopback HTTP endpoint."
  }
}

variable "bucket_prefix" {
  type    = string
  default = "tfpro-c17"

  # TODO: 只接受 3-30 位小写字母、数字和连字符，首尾必须为字母或数字。
}
