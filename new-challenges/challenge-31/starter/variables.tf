variable "name_prefix" {
  type    = string
  default = "tfpro-c31"
}

variable "run_id" {
  type    = string
  default = "manual-c31"
}

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "localstack_endpoint" {
  type    = string
  default = "http://localhost:4566"
  validation {
    condition = (
      can(regex("^https?://(localhost|127\\.0\\.0\\.1|\\[::1\\]):([1-9][0-9]{0,4})\\z", var.localstack_endpoint)) &&
      try(tonumber(regex("^https?://(localhost|127\\.0\\.0\\.1|\\[::1\\]):([1-9][0-9]{0,4})\\z", var.localstack_endpoint)[1]) <= 65535, false)
    )
    error_message = "localstack_endpoint 必须是带显式有效端口的 loopback origin。"
  }
}

variable "environment" {
  type    = string
  default = "prod"
  # TODO: 只允许 dev/stage/prod。
}

variable "fleet_csv_path" {
  type    = string
  default = "../fixtures/fleets.csv"
  # TODO: 安全验证 CSV 可解析。
}

variable "subnet_ids" {
  type        = map(string)
  description = "grader-owned subnet IDs keyed by business subnet name"
  default     = { replace = "subnet-replace-me" }
  # TODO: 非空、key 格式、subnet ID 格式和 ID 唯一性。
}
