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
}

variable "name_prefix" {
  type    = string
  default = "tfpro-c30"
}

variable "run_id" {
  type    = string
  default = "manual-c30"
}

variable "state_bucket" {
  type    = string
  default = "replace-me"
}

variable "foundation_state_key" {
  type    = string
  default = "foundation.tfstate"
}
