variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "localstack_endpoint" {
  type    = string
  default = "http://localhost:4566"

  validation {
    condition     = can(regex("^https?://(localhost|127[.]0[.]0[.]1|\\[::1\\]):([1-9][0-9]{0,3}|[1-5][0-9]{4}|6[0-4][0-9]{3}|65[0-4][0-9]{2}|655[0-2][0-9]|6553[0-5])\\z", var.localstack_endpoint))
    error_message = "localstack_endpoint 必须是带显式有效端口的纯 loopback HTTP(S) origin。"
  }
}

variable "run_id" {
  type    = string
  default = "tfpro-c39"
  validation {
    condition     = can(regex("^[a-z0-9-]{3,32}$", var.run_id))
    error_message = "run_id 非法。"
  }
}

variable "contract_version" {
  type    = number
  default = 1
}

variable "state_bucket" {
  type = string
}

variable "producer_state_key" {
  type    = string
  default = "producer/terraform.tfstate"
}
