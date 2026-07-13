variable "run_id" {
  type    = string
  default = "tfpro-c35"
  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{4,16}[a-z0-9]$", var.run_id))
    error_message = "run_id must be 6-18 lowercase letters, digits, or hyphens."
  }
}
variable "primary_region" {
  type    = string
  default = "us-east-1"
}
variable "dr_region" {
  type    = string
  default = "us-west-2"
}
variable "primary_vpc_cidr" {
  type    = string
  default = "10.35.0.0/16"
}
variable "dr_vpc_cidr" {
  type    = string
  default = "10.36.0.0/16"
}
variable "localstack_endpoint" {
  type        = string
  description = "LocalStack edge endpoint"
  default     = "http://localhost:4566"
  validation {
    condition     = can(regex("^https?://(localhost|127\\.0\\.0\\.1|\\[::1\\]):[0-9]+$", var.localstack_endpoint))
    error_message = "localstack_endpoint must be an HTTP(S) loopback endpoint."
  }
}
