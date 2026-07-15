variable "localstack_endpoint" {
  type    = string
  default = "http://localhost:4566"
  validation {
    condition     = can(regex("^http://(localhost|127\\.0\\.0\\.1|\\[::1\\]):([1-9][0-9]{0,4})\\z", var.localstack_endpoint)) && try(tonumber(regex("^http://(localhost|127\\.0\\.0\\.1|\\[::1\\]):([1-9][0-9]{0,4})\\z", var.localstack_endpoint)[1]) <= 65535, false)
    error_message = "localstack_endpoint must be an explicit loopback HTTP root origin."
  }
}
variable "region" {
  type    = string
  default = "us-east-1"
  validation {
    condition     = var.region == "us-east-1"
    error_message = "This IAM compiler is fixed to us-east-1."
  }
}
variable "run_id" {
  type    = string
  default = "tfpro-c43"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,19}$", var.run_id))
    error_message = "run_id must be 3-20 lowercase letters, digits, or hyphens."
  }
}
variable "directory_path" {
  type    = string
  default = "../fixtures/permissions.json"
  validation {
    condition     = length(trimspace(var.directory_path)) > 0
    error_message = "directory_path must not be empty."
  }
}
