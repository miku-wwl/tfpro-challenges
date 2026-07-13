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
  default = "tfpro-c34"
}

variable "ami_name_pattern" {
  type    = string
  default = "amzn2-ami-hvm-*-x86_64-gp2"
}
