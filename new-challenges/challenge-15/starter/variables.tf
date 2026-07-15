variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "localstack_endpoint" {
  type    = string
  default = "http://localhost:4566"
  validation {
    condition     = can(regex("^http://(localhost|127\\.0\\.0\\.1):([1-9][0-9]{0,3}|[1-5][0-9]{4}|6[0-4][0-9]{3}|65[0-4][0-9]{2}|655[0-2][0-9]|6553[0-5])$", var.localstack_endpoint))
    error_message = "localstack_endpoint must be a loopback HTTP origin with a valid port."
  }
}

variable "name_prefix" {
  type    = string
  default = "tfpro-c15"
  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{2,30}[a-z0-9]$", var.name_prefix))
    error_message = "name_prefix must be 4-32 lowercase letters, digits, or hyphens."
  }
}

variable "network_name" {
  type    = string
  default = "tfpro-c15-network"
}

variable "target_environment" {
  type    = string
  default = "prod"
  validation {
    condition     = contains(["dev", "staging", "prod"], var.target_environment)
    error_message = "target_environment must be dev, staging, or prod."
  }
}

variable "subnet_tiers" {
  type    = set(string)
  default = ["app", "data"]
}

variable "rules_file" {
  type    = string
  default = "../fixtures/rules.csv"
}

variable "source_aliases" {
  type = map(string)
  default = {
    office   = "203.0.113.0/24"
    partners = "198.51.100.0/24"
  }
}
