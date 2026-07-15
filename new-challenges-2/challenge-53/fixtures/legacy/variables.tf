variable "localstack_endpoint" { type = string }
variable "run_id" { type = string }
variable "primary_subnet_id" { type = string }
variable "dr_subnet_id" { type = string }

variable "primary_region" {
  type    = string
  default = "us-east-1"
}

variable "dr_region" {
  type    = string
  default = "us-west-2"
}

variable "ami_pattern" {
  type    = string
  default = "al2023-ami-*"
}
