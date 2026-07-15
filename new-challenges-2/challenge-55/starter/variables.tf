variable "aws_region" {
  type    = string
  default = "us-east-1"
}
variable "localstack_endpoint" {
  type    = string
  default = "http://localhost:4566"
  validation {
    condition     = can(regex("^https?://(?:localhost|127\\.0\\.0\\.1|\\[::1\\]):[0-9]{1,5}$", var.localstack_endpoint))
    error_message = "LocalStack endpoint must be a loopback root origin."
  }
}
variable "run_id" {
  type = string
  validation {
    condition     = can(regex("^[a-z][a-z0-9]{7,15}$", var.run_id))
    error_message = "run_id is invalid."
  }
}
variable "subnet_id" {
  type = string
  validation {
    condition     = can(regex("^subnet-[0-9a-f]+$", var.subnet_id))
    error_message = "subnet_id is invalid."
  }
}
variable "catalog_path" {
  type    = string
  default = "fixtures/catalog-v1.json"
}
variable "ami_name_pattern" {
  type    = string
  default = "al2023-ami-*"
}
