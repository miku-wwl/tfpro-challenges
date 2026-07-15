variable "run_id" {
  type = string
  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{5,23}$", var.run_id))
    error_message = "run_id must contain 6-24 lowercase letters, digits, or hyphens."
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
    condition     = can(regex("^https?://(localhost|127\\.0\\.0\\.1|\\[::1\\]):([1-9][0-9]{0,4})$", var.localstack_endpoint)) && try(tonumber(regex("^https?://(?:localhost|127\\.0\\.0\\.1|\\[::1\\]):([1-9][0-9]{0,4})$", var.localstack_endpoint)[0]) <= 65535, false)
    error_message = "Use a loopback LocalStack endpoint with a valid explicit port."
  }
}
variable "state_bucket" {
  type = string
  validation {
    condition     = can(regex("^tfpro-c48-state-[a-z0-9]{10}$", var.state_bucket))
    error_message = "state_bucket must match the external grader contract."
  }
}
variable "foundation_state_key" {
  type    = string
  default = "foundation/terraform.tfstate"
  validation {
    condition     = var.foundation_state_key == "foundation/terraform.tfstate"
    error_message = "Use the canonical foundation state key."
  }
}
variable "expected_revision" {
  type = string
  validation {
    condition     = can(regex("^v[1-9][0-9]*$", var.expected_revision))
    error_message = "expected_revision must look like v1."
  }
}
variable "manifest_path" {
  type    = string
  default = "../../fixtures/grants.json"
  validation {
    condition     = can(jsondecode(file(var.manifest_path)))
    error_message = "manifest_path must point to readable JSON."
  }
}
