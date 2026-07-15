variable "run_id" {
  type = string
  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{5,19}$", var.run_id))
    error_message = "Invalid run_id."
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

variable "platform_state_key" {
  type    = string
  default = "platform/terraform.tfstate"
  validation {
    condition     = var.platform_state_key == "platform/terraform.tfstate"
    error_message = "Invalid platform state key."
  }
}

variable "expected_release" {
  type = string
  validation {
    condition     = can(regex("^[0-9]{4}\\.[0-9]{2}\\.[0-9]+$", var.expected_release))
    error_message = "Invalid expected release."
  }
}

variable "catalog_path" {
  type    = string
  default = "../../fixtures/fleets.json"
  validation {
    condition     = can(jsondecode(file(var.catalog_path)))
    error_message = "Invalid catalog path."
  }
}

variable "primary_subnet_id" {
  type = string
  validation {
    condition     = can(regex("^subnet-[0-9a-f]{8,17}$", var.primary_subnet_id))
    error_message = "Invalid subnet."
  }
}

variable "dr_subnet_id" {
  type = string
  validation {
    condition     = can(regex("^subnet-[0-9a-f]{8,17}$", var.dr_subnet_id))
    error_message = "Invalid subnet."
  }
}

variable "primary_image_id" {
  type = string
  validation {
    condition     = can(regex("^ami-[0-9a-f]{8,17}$", var.primary_image_id))
    error_message = "Invalid AMI."
  }
}

variable "dr_image_id" {
  type = string
  validation {
    condition     = can(regex("^ami-[0-9a-f]{8,17}$", var.dr_image_id))
    error_message = "Invalid AMI."
  }
}
