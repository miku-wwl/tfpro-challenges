variable "aws_region" {
  type    = string
  default = "us-east-1"
  # TODO: restrict this lab to us-east-1.
}

variable "localstack_endpoint" {
  type    = string
  default = "http://localhost:4566"
  # TODO: require a loopback root origin with an explicit valid port.
}

variable "name_prefix" {
  type    = string
  default = "tfpro-c25"
  # TODO: validate a safe lowercase prefix.
}

variable "application" {
  type    = string
  default = "checkout"
}

variable "environment" {
  type    = string
  default = "dev"
  # TODO: allow only dev, stage, prod.
}

variable "config_version" {
  type    = number
  default = 1
  # TODO: require a positive integer.
}

variable "config_path" {
  type    = string
  default = "../fixtures/config-v1.json"
}
