variable "name_prefix" {
  type    = string
  default = "tfpro-alias"
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
    condition     = can(regex("^http://(localhost|127\\.0\\.0\\.1):[0-9]+$", var.localstack_endpoint))
    error_message = "localstack_endpoint must be a loopback HTTP endpoint."
  }
}

variable "common_tags" {
  type = map(string)
  default = {
    managed_by = "terraform"
    exercise   = "challenge-11"
  }
}
