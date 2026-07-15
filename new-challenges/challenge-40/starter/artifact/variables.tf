variable "run_id" {
  type        = string
  description = "本次发布的隔离标识，也用于 S3 bucket 名称。"
  default     = "tfpro-c40"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{4,20}[a-z0-9]$", var.run_id))
    error_message = "run_id must be 6-22 lowercase letters, digits, or hyphens."
  }
}

variable "aws_region" {
  type        = string
  description = "LocalStack 使用的制品区域。"
  default     = "us-east-1"
}

variable "localstack_endpoint" {
  type        = string
  description = "LocalStack loopback edge endpoint。"
  default     = "http://localhost:4566"

  validation {
    condition = (
      can(regex("^https?://(localhost|127\\.0\\.0\\.1|\\[::1\\]):([1-9][0-9]{0,4})\\z", var.localstack_endpoint)) &&
      try(tonumber(regex("^https?://(localhost|127\\.0\\.0\\.1|\\[::1\\]):([1-9][0-9]{0,4})\\z", var.localstack_endpoint)[1]) <= 65535, false)
    )
    error_message = "localstack_endpoint must be a loopback HTTP(S) origin with an explicit port from 1 to 65535."
  }
}

variable "manifest_path" {
  type        = string
  description = "相对 artifact root 的发布 manifest 路径。"
  default     = "../../fixtures/manifest-v1.json"
}
