variable "run_id" {
  type    = string
  default = "tfpro-c42"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,21}$", var.run_id))
    error_message = "run_id must be 5-22 lowercase letters, digits, or hyphens and start with a letter."
  }
}
variable "primary_region" {
  type    = string
  default = "us-east-1"
}
variable "dr_region" {
  type    = string
  default = "us-west-2"
}
variable "audit_region" {
  type    = string
  default = "eu-west-1"
}
variable "routes_path" {
  type    = string
  default = "../fixtures/routes.json"
}
variable "localstack_endpoint" {
  type    = string
  default = "http://localhost:4566"
  validation {
    condition     = can(regex("^http://(localhost|127\\.0\\.0\\.1|\\[::1\\]):([1-9][0-9]{0,4})\\z", var.localstack_endpoint)) && try(tonumber(regex("^http://(localhost|127\\.0\\.0\\.1|\\[::1\\]):([1-9][0-9]{0,4})\\z", var.localstack_endpoint)[1]) <= 65535, false)
    error_message = "localstack_endpoint must be an explicit loopback HTTP root origin."
  }
}
