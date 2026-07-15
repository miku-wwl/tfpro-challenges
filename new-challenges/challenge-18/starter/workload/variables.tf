variable "state_bucket" { type = string }
variable "foundation_state_key" { type = string }
variable "primary_region" {
  type    = string
  default = "us-east-1"
}
variable "dr_region" {
  type    = string
  default = "us-west-2"
}
variable "localstack_endpoint" {
  type    = string
  default = "http://localhost:4566"
  validation {
    condition     = can(regex("^http://(localhost|127\\.0\\.0\\.1):([1-9][0-9]{0,3}|[1-5][0-9]{4}|6[0-4][0-9]{3}|65[0-4][0-9]{2}|655[0-2][0-9]|6553[0-5])$", var.localstack_endpoint))
    error_message = "localstack_endpoint must be a loopback HTTP origin with a valid port."
  }
}
variable "catalog_file" {
  type    = string
  default = "../../fixtures/services.csv"
}
variable "target_environment" {
  type    = string
  default = "prod"
  validation {
    condition     = contains(["dev", "stage", "prod"], var.target_environment)
    error_message = "target_environment must be dev, stage, or prod."
  }
}
