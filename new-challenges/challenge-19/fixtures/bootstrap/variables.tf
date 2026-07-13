variable "name_prefix" {
  type = string
}

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "localstack_endpoint" {
  type    = string
  default = "http://localhost:4566"

  validation {
    condition     = can(regex("^https?://(localhost|127\\.0\\.0\\.1)(:[0-9]+)?/?$", var.localstack_endpoint))
    error_message = "localstack_endpoint must use localhost or 127.0.0.1"
  }
}
