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
    error_message = "Invalid endpoint."
  }
}

variable "state_bucket" {
  type = string
  validation {
    condition     = can(regex("^tfpro-c50-state-[a-z0-9]{10}$", var.state_bucket))
    error_message = "Invalid state bucket."
  }
}

variable "identity_state_key" {
  type    = string
  default = "identity/terraform.tfstate"
  validation {
    condition     = var.identity_state_key == "identity/terraform.tfstate"
    error_message = "Invalid identity state key."
  }
}

variable "manifest_path" {
  type    = string
  default = "../../fixtures/manifest-v1.json"
  validation {
    condition     = can(jsondecode(file(var.manifest_path)))
    error_message = "Invalid manifest path."
  }
}
