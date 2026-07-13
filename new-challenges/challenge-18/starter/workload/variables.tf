variable "foundation_state_path" {
  description = "Path to the foundation local state for this offline lab."
  type        = string
  default     = "../foundation/terraform.tfstate"
}

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

variable "catalog_file" {
  type    = string
  default = "../../fixtures/services.csv"
}

variable "target_environment" {
  type    = string
  default = "prod"

  validation {
    # TODO: Reject any environment outside the supported set.
    condition     = length(trimspace(var.target_environment)) > 0
    error_message = "target_environment must not be empty."
  }
}
