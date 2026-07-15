variable "name_prefix" {
  type    = string
  default = "tfpro-c11"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{2,30}[a-z0-9]$", var.name_prefix))
    error_message = "name_prefix must be 4-32 lowercase letters, digits, or hyphens and must start/end alphanumeric."
  }
}

variable "primary_region" {
  type    = string
  default = "us-east-1"
}

variable "recovery_region" {
  type    = string
  default = "us-west-2"
}

variable "localstack_endpoint" {
  type        = string
  description = "LocalStack edge endpoint."
  default     = "http://localhost:4566"

  validation {
    condition     = can(regex("^http://(localhost|127\\.0\\.0\\.1):([1-9][0-9]{0,3}|[1-5][0-9]{4}|6[0-4][0-9]{3}|65[0-4][0-9]{2}|655[0-2][0-9]|6553[0-5])$", var.localstack_endpoint))
    error_message = "localstack_endpoint must be a loopback HTTP origin with a port from 1 to 65535."
  }
}

variable "common_tags" {
  type = map(string)
  default = {
    managed_by = "terraform"
    exercise   = "challenge-11"
  }
}
