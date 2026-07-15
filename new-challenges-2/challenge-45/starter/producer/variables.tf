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

variable "release_version" {
  type = string

  validation {
    condition     = length(regexall("^v[1-9][0-9]*$", var.release_version)) == 1
    error_message = "release_version must look like v1."
  }
}

variable "payloads" {
  type = map(string)
}
