variable "run_id" {
  type    = string
  default = "tfpro-c28"
}

variable "network_state_path" {
  type    = string
  default = "../network/terraform.tfstate"
}

variable "catalog_file" {
  type    = string
  default = "../../fixtures/applications.csv"
}

variable "target_environment" {
  type    = string
  default = "prod"
  # TODO: Reject unknown environments.
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
    condition     = can(regex("^http://(localhost|127\\.0\\.0\\.1):[0-9]+$", var.localstack_endpoint))
    error_message = "localstack_endpoint must be loopback."
  }
}

