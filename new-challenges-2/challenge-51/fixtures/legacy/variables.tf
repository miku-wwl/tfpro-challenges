variable "localstack_endpoint" { type = string }

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "run_id" { type = string }
variable "subnet_id" { type = string }
variable "role_name" { type = string }
variable "profile_name" { type = string }

variable "ami_name_pattern" {
  type    = string
  default = "al2023-ami-*"
}
