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
    condition     = can(regex("^https?://(localhost|127\\.0\\.0\\.1|\\[::1\\]):([1-9][0-9]{0,4})$", var.localstack_endpoint)) && try(tonumber(regex("^https?://(?:localhost|127\\.0\\.0\\.1|\\[::1\\]):([1-9][0-9]{0,4})$", var.localstack_endpoint)[0]) <= 65535, false)
    error_message = "Use a loopback LocalStack endpoint with a valid port."
  }
}
variable "run_id" {
  type = string
  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{5,19}$", var.run_id))
    error_message = "Invalid run_id."
  }
}
variable "catalog_path" {
  type    = string
  default = "../fixtures/catalog-v1.json"
  validation {
    condition     = can(jsondecode(file(var.catalog_path)))
    error_message = "catalog_path must point to readable JSON."
  }
}
variable "primary_subnet_id" {
  type = string
  validation {
    condition     = can(regex("^subnet-[0-9a-f]{8,17}$", var.primary_subnet_id))
    error_message = "Invalid primary subnet ID."
  }
}
variable "dr_subnet_id" {
  type = string
  validation {
    condition     = can(regex("^subnet-[0-9a-f]{8,17}$", var.dr_subnet_id))
    error_message = "Invalid DR subnet ID."
  }
}
variable "primary_image_id" {
  type = string
  validation {
    condition     = can(regex("^ami-[0-9a-f]{8,17}$", var.primary_image_id))
    error_message = "Invalid primary AMI ID."
  }
}
variable "dr_image_id" {
  type = string
  validation {
    condition     = can(regex("^ami-[0-9a-f]{8,17}$", var.dr_image_id))
    error_message = "Invalid DR AMI ID."
  }
}
