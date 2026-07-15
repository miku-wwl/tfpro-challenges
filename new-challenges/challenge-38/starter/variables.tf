variable "primary_region" {
  type    = string
  default = "us-east-1"
}

variable "dr_region" {
  type    = string
  default = "us-west-2"
}

variable "localstack_endpoint" {
  type        = string
  description = "LocalStack edge endpoint"
  default     = "http://localhost:4566"

  validation {
    condition = (
      can(regex("^https?://(localhost|127\\.0\\.0\\.1|\\[::1\\]):([1-9][0-9]{0,4})\\z", var.localstack_endpoint)) &&
      try(tonumber(regex("^https?://(localhost|127\\.0\\.0\\.1|\\[::1\\]):([1-9][0-9]{0,4})\\z", var.localstack_endpoint)[1]) <= 65535, false)
    )
    error_message = "localstack_endpoint 只能是带显式有效端口的 loopback HTTP(S) 根地址。"
  }
}

variable "run_id" {
  type    = string
  default = "tfpro-c38"

  validation {
    condition     = can(regex("^[a-z0-9-]{3,32}$", var.run_id))
    error_message = "run_id 必须是 3-32 位小写字母、数字或连字符。"
  }
}

variable "ami_name_pattern" {
  type    = string
  default = "amzn2-ami-hvm-*-x86_64-gp2"
}
