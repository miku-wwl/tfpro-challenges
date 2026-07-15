variable "aws_region" {
  type    = string
  default = "us-east-1"

  validation {
    condition     = var.aws_region == "us-east-1"
    error_message = "Challenge 46 runs in LocalStack us-east-1."
  }
}
variable "localstack_endpoint" {
  type    = string
  default = "http://localhost:4566"

  validation {
    condition = (
      length(regexall("^https?://(localhost|127\\.0\\.0\\.1|\\[::1\\]):([1-9][0-9]{0,4})$", var.localstack_endpoint)) == 1 &&
      try(tonumber(regex("^https?://(?:localhost|127\\.0\\.0\\.1|\\[::1\\]):([1-9][0-9]{0,4})$", var.localstack_endpoint)[0]), 65536) <= 65535
    )
    error_message = "Use an HTTP(S) loopback root endpoint with an explicit valid port."
  }
}

variable "run_id" {
  type = string

  validation {
    condition     = length(regexall("^[a-z0-9][a-z0-9-]{5,23}$", var.run_id)) == 1
    error_message = "run_id must be 6-24 lowercase letters, digits, or hyphens."
  }
}

variable "catalog_path" {
  type    = string
  default = "../fixtures/catalog-v1.json"

  validation {
    condition = (
      length(trimspace(var.catalog_path)) > 0 &&
      length(regexall("[.]json$", var.catalog_path)) == 1 &&
      length(regexall("[\\r\\n]", var.catalog_path)) == 0
    )
    error_message = "catalog_path must be a nonblank JSON path without CR/LF."
  }
}
