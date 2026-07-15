variable "aws_region" {
  type    = string
  default = "us-east-1"

  validation {
    condition     = var.aws_region == "us-east-1"
    error_message = "This lab uses us-east-1."
  }
}

variable "localstack_endpoint" {
  type    = string
  default = "http://localhost:4566"

  validation {
    condition = (
      length(regexall("^http://(localhost|127\\.0\\.0\\.1|\\[::1\\]):([1-9][0-9]{0,4})$", var.localstack_endpoint)) == 1 &&
      try(tonumber(regex("^http://(?:localhost|127\\.0\\.0\\.1|\\[::1\\]):([1-9][0-9]{0,4})$", var.localstack_endpoint)[0]), 65536) <= 65535
    )
    error_message = "Use a loopback root origin with an explicit valid port."
  }
}

variable "run_id" {
  type = string

  validation {
    condition     = length(regexall("^[a-z0-9][a-z0-9-]{5,23}$", var.run_id)) == 1
    error_message = "run_id is invalid."
  }
}

variable "state_bucket" {
  type = string

  validation {
    condition     = length(regexall("^tfpro-c45-state-[a-z0-9]{10}$", var.state_bucket)) == 1
    error_message = "state_bucket does not match the platform contract."
  }
}

variable "producer_state_key" {
  type    = string
  default = "producer/terraform.tfstate"

  validation {
    condition     = var.producer_state_key == "producer/terraform.tfstate"
    error_message = "Use the canonical producer state key."
  }
}

variable "expected_release_version" {
  type = string

  validation {
    condition     = length(regexall("^v[1-9][0-9]*$", var.expected_release_version)) == 1
    error_message = "expected_release_version must look like v1."
  }
}

variable "required_artifacts" {
  type    = set(string)
  default = ["api", "worker"]

  validation {
    condition = (
      length(var.required_artifacts) > 0 &&
      alltrue([for name in var.required_artifacts : length(regexall("^[a-z][a-z0-9-]{1,31}$", name)) == 1])
    )
    error_message = "required_artifacts must contain safe logical names."
  }
}
