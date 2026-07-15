variable "run_id" {
  type = string

  validation {
    condition     = can(regex("^c58-[a-z0-9]{8,12}$", var.run_id))
    error_message = "run_id must match c58- followed by 8 to 12 lowercase letters or digits."
  }
}

variable "catalog_path" {
  type    = string
  default = "../fixtures/identities-v1.json"

  validation {
    condition     = length(trimspace(var.catalog_path)) > 0
    error_message = "catalog_path must not be blank."
  }
}

variable "localstack_endpoint" {
  type    = string
  default = "http://localhost:4566"

  validation {
    condition     = can(regex("^http://(?:localhost|127\\.0\\.0\\.1|\\[::1\\]):[1-9][0-9]{0,4}$", var.localstack_endpoint))
    error_message = "localstack_endpoint must be an explicit loopback HTTP root origin."
  }
}
