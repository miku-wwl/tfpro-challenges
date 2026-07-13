variable "name_prefix" {
  type = string
}

variable "role" {
  type = string

  validation {
    condition     = contains(["primary", "dr"], var.role)
    error_message = "role must be primary or dr"
  }
}

variable "expected_region" {
  type = string
}

variable "peer_bucket" {
  type = string
}

