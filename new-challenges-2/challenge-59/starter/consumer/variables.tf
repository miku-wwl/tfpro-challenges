variable "run_id" {
  type = string
  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{5,19}$", var.run_id))
    error_message = "run_id must contain 6-20 lowercase letters, digits, or hyphens."
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
    error_message = "Use a loopback LocalStack endpoint with an explicit port."
  }
}

variable "state_bucket" {
  type = string
  validation {
    condition     = can(regex("^tfpro-c59-state-[a-z0-9]{10}$", var.state_bucket))
    error_message = "state_bucket must match the grader-owned state contract."
  }
}

variable "publisher_state_key" {
  type    = string
  default = "publisher/terraform.tfstate"
  validation {
    condition     = var.publisher_state_key == "publisher/terraform.tfstate"
    error_message = "Use the canonical publisher state key."
  }
}

variable "expected_revision" {
  type = string
  validation {
    condition     = can(regex("^[0-9]{4}\\.[0-9]{2}\\.[0-9]+$", var.expected_revision))
    error_message = "expected_revision must use YYYY.MM.N format."
  }
}

variable "manifest_path" {
  type    = string
  default = "../../fixtures/deployments.json"
  validation {
    condition     = can(jsondecode(file(var.manifest_path)))
    error_message = "manifest_path must point to readable JSON."
  }
}

variable "subnet_id" {
  type = string
  validation {
    condition     = can(regex("^subnet-[0-9a-f]{8,17}$", var.subnet_id))
    error_message = "subnet_id must be an injected EC2 subnet ID."
  }
}

variable "image_name" {
  type = string
  validation {
    condition     = can(regex("^tfpro-c59-[a-z0-9-]{6,24}$", var.image_name))
    error_message = "image_name must match the grader-registered AMI contract."
  }
}
