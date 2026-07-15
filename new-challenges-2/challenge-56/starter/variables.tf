variable "name_prefix" {
  type    = string
  default = "tfpro-c56"
}

variable "run_id" {
  type    = string
  default = "manual-c56"
}

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "localstack_endpoint" {
  type    = string
  default = "http://localhost:4566"
  validation {
    condition = (
      can(regex("^https?://(localhost|127\\.0\\.0\\.1|\\[::1\\]):([1-9][0-9]{0,4})\\z", var.localstack_endpoint)) &&
      try(tonumber(regex("^https?://(localhost|127\\.0\\.0\\.1|\\[::1\\]):([1-9][0-9]{0,4})\\z", var.localstack_endpoint)[1]) <= 65535, false)
    )
    error_message = "localstack_endpoint must be a loopback root origin with an explicit valid port."
  }
}

variable "environment" {
  type    = string
  default = "prod"
  # TODO: Allow only dev, stage, or prod.
}

variable "fleet_csv_path" {
  type    = string
  default = "../fixtures/fleets.csv"
  # TODO: Reject missing or undecodable files safely.
}

variable "subnet_ids" {
  type        = map(string)
  description = "Grader-owned subnet IDs keyed by business subnet name."
  default     = { replace = "subnet-replace-me" }
  # TODO: Validate non-empty safe keys, subnet IDs, and unique values.
}

variable "ami_name_pattern" {
  type    = string
  default = "al2023-ami-*"
}
