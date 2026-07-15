variable "run_id" {
  type = string
  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{5,19}$", var.run_id))
    error_message = "Invalid run_id."
  }
}
variable "aws_region" {
  type    = string
  default = "us-east-1"
}
variable "localstack_endpoint" {
  type    = string
  default = "http://localhost:4566"
  validation {
    condition     = can(regex("^https?://(localhost|127\\.0\\.0\\.1|\\[::1\\]):([1-9][0-9]{0,4})$", var.localstack_endpoint))
    error_message = "Invalid LocalStack endpoint."
  }
}
variable "contract_version" {
  type    = number
  default = 1
}
