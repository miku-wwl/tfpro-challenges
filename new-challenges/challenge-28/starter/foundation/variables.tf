variable "run_id" {
  type = string
  # TODO: validate a safe lowercase run identity.
}

variable "platform_revision" {
  type = number
  # TODO: require a positive integer.
}

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
  # TODO: require a loopback root origin with an explicit valid port.
}
