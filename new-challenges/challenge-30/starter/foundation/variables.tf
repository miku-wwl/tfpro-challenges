variable "aws_region" {
  type    = string
  default = "us-east-1"
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
