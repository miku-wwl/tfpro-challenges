variable "state_bucket" {
  type = string
}

variable "producer_state_key" {
  type = string
}

variable "name_prefix" {
  type    = string
  default = "tfpro-c12"
}

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "localstack_endpoint" {
  type    = string
  default = "http://localhost:4566"

  validation {
    condition     = can(regex("^http://(localhost|127\\.0\\.0\\.1):([1-9][0-9]{0,3}|[1-5][0-9]{4}|6[0-4][0-9]{3}|65[0-4][0-9]{2}|655[0-2][0-9]|6553[0-5])$", var.localstack_endpoint))
    error_message = "localstack_endpoint must be a loopback HTTP origin with a valid port."
  }
}
