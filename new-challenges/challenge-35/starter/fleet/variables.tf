variable "run_id" {
  type    = string
  default = "manual-c35"
}
variable "fleet_csv_path" {
  type    = string
  default = "../../fixtures/fleet.csv"
}
variable "target_environment" {
  type    = string
  default = "prod"
  validation {
    condition     = contains(["dev", "stage", "prod"], var.target_environment)
    error_message = "target_environment must be dev, stage, or prod."
  }
}
variable "state_bucket" {
  type = string
}
variable "foundation_state_key" {
  type    = string
  default = "states/foundation.tfstate"
}
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
    condition     = can(regex("^https?://(localhost|127\\.0\\.0\\.1|\\[::1\\]):([1-9][0-9]{0,4})\\z", var.localstack_endpoint)) && try(tonumber(regex("^https?://(localhost|127\\.0\\.0\\.1|\\[::1\\]):([1-9][0-9]{0,4})\\z", var.localstack_endpoint)[1]) <= 65535, false)
    error_message = "localstack_endpoint must be an explicit-port loopback origin."
  }
}
