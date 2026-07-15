variable "run_id" {
  type    = string
  default = "manual-c40"
}
variable "primary_region" {
  type    = string
  default = "us-east-1"
}
variable "dr_region" {
  type    = string
  default = "us-west-2"
}
variable "primary_subnet_id" { type = string }
variable "dr_subnet_id" { type = string }
variable "state_bucket" { type = string }
variable "artifact_state_key" {
  type    = string
  default = "states/artifact.tfstate"
}
variable "runtime_catalog_path" {
  type    = string
  default = "../../fixtures/runtime.json"
}
variable "localstack_endpoint" {
  type    = string
  default = "http://localhost:4566"
  validation {
    condition     = can(regex("^https?://(localhost|127\\.0\\.0\\.1|\\[::1\\]):([1-9][0-9]{0,4})\\z", var.localstack_endpoint)) && try(tonumber(regex("^https?://(localhost|127\\.0\\.0\\.1|\\[::1\\]):([1-9][0-9]{0,4})\\z", var.localstack_endpoint)[1]) <= 65535, false)
    error_message = "localstack_endpoint must be an explicit-port loopback origin."
  }
}
