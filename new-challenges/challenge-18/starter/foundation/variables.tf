variable "primary_region" {
  type        = string
  description = "LocalStack primary region."
  default     = "us-east-1"
}

variable "dr_region" {
  type        = string
  description = "LocalStack recovery region."
  default     = "us-west-2"
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

