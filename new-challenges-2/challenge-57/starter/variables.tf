variable "run_id" {
  description = "Unique grader or learner run identifier."
  type        = string

  validation {
    condition     = can(regex("^c57-[a-z0-9]{8,12}$", var.run_id))
    error_message = "run_id must match c57- followed by 8 to 12 lowercase letters or digits."
  }
}

variable "catalog_path" {
  description = "Path to the release catalog, relative to the root module."
  type        = string
  default     = "../fixtures/releases-v1.json"

  validation {
    condition     = length(trimspace(var.catalog_path)) > 0
    error_message = "catalog_path must not be blank."
  }
}

variable "localstack_endpoint" {
  description = "Explicit loopback LocalStack root origin."
  type        = string
  default     = "http://localhost:4566"

  validation {
    condition     = can(regex("^http://(?:localhost|127\\.0\\.0\\.1|\\[::1\\]):[1-9][0-9]{0,4}$", var.localstack_endpoint))
    error_message = "localstack_endpoint must be an explicit loopback HTTP root origin."
  }
}

variable "primary_region" {
  type    = string
  default = "us-east-1"
}

variable "replica_region" {
  type    = string
  default = "us-west-2"
}
