variable "primary_region" {
  type    = string
  default = "us-east-1"
  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[1-9][0-9]*$", var.primary_region))
    error_message = "primary_region must be a valid AWS region identifier."
  }
}

variable "audit_region" {
  type    = string
  default = "us-west-2"
  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[1-9][0-9]*$", var.audit_region))
    error_message = "audit_region must be a valid AWS region identifier."
  }
}

variable "localstack_endpoint" {
  type    = string
  default = "http://localhost:4566"
  validation {
    condition = (
      can(regex("^https?://(localhost|127\\.0\\.0\\.1|\\[::1\\]):([1-9][0-9]{0,4})$", var.localstack_endpoint)) &&
      try(tonumber(regex("^https?://(?:localhost|127\\.0\\.0\\.1|\\[::1\\]):([1-9][0-9]{0,4})$", var.localstack_endpoint)[0]) <= 65535, false)
    )
    error_message = "Use a loopback LocalStack root endpoint with an explicit valid port."
  }
}

variable "run_id" {
  type = string
  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{5,23}$", var.run_id))
    error_message = "run_id must contain 6-24 lowercase letters, digits, or hyphens."
  }
}

variable "primary_subnet_id" {
  type = string
  validation {
    condition     = can(regex("^subnet-[0-9a-f]{8,17}$", var.primary_subnet_id))
    error_message = "primary_subnet_id must be an injected subnet ID."
  }
}

variable "audit_subnet_id" {
  type = string
  validation {
    condition     = can(regex("^subnet-[0-9a-f]{8,17}$", var.audit_subnet_id))
    error_message = "audit_subnet_id must be an injected subnet ID."
  }
}

variable "instance_type" {
  type    = string
  default = "t3.micro"
  validation {
    condition     = contains(["t3.micro", "t3.small"], var.instance_type)
    error_message = "instance_type must be t3.micro or t3.small."
  }
}

variable "catalog_path" {
  type    = string
  default = "../fixtures/routes.json"
  validation {
    condition     = can(jsondecode(file(var.catalog_path)))
    error_message = "catalog_path must point to readable JSON."
  }
}
