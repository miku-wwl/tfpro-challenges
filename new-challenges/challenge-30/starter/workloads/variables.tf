variable "run_id" {
  type    = string
  default = "tfpro-c30"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{4,16}[a-z0-9]$", var.run_id))
    error_message = "run_id must be 6-18 lowercase letters, digits, or hyphens."
  }
}

variable "catalog_file" {
  type    = string
  default = "../../fixtures/workloads.csv"
}

variable "target_environment" {
  type    = string
  default = "prod"

  validation {
    condition     = contains(["dev", "stage", "prod"], var.target_environment)
    error_message = "target_environment must be dev, stage, or prod."
  }
}

variable "foundation_state_path" {
  type    = string
  default = "../foundation/terraform.tfstate"
}

variable "platform_state_path" {
  type    = string
  default = "../platform/terraform.tfstate"
}

variable "primary_region" {
  type    = string
  default = "us-east-1"
}

variable "dr_region" {
  type    = string
  default = "us-west-2"

  validation {
    condition     = var.dr_region != var.primary_region
    error_message = "dr_region must differ from primary_region."
  }
}

variable "localstack_endpoint" {
  type    = string
  default = "http://localhost:4566"

  validation {
    condition     = can(regex("^http://(localhost|127\\.0\\.0\\.1):[0-9]+$", var.localstack_endpoint))
    error_message = "localstack_endpoint must be a loopback HTTP endpoint."
  }
}
