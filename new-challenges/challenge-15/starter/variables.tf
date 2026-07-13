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
    condition     = can(regex("^http://(localhost|127\\.0\\.0\\.1):[0-9]+$", var.localstack_endpoint))
    error_message = "localstack_endpoint must be a loopback HTTP endpoint."
  }
}

variable "target_environment" {
  type    = string
  default = "prod"

  # TODO: 只允许 dev、staging、prod。
}

variable "vpc_name" {
  type    = string
  default = "shared-services"
}

variable "subnet_tiers" {
  type    = set(string)
  default = ["app", "data"]
}

variable "rules_file" {
  type    = string
  default = "../fixtures/rules.csv"
}

variable "source_aliases" {
  type = map(string)
  default = {
    office   = "203.0.113.0/24"
    partners = "198.51.100.0/24"
  }
}
