variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "localstack_endpoint" {
  type    = string
  default = "http://localhost:4566"
}

variable "run_id" { type = string }
variable "subnet_id" { type = string }
variable "legacy_role_name" { type = string }
variable "legacy_profile_name" { type = string }
variable "legacy_instance_id" { type = string }

variable "catalog_path" {
  type    = string
  default = "fixtures/takeover.json"
}

variable "ami_name_pattern" {
  type    = string
  default = "al2023-ami-*"
}
