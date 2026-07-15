variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "localstack_endpoint" {
  type    = string
  default = "http://localhost:4566"
}

variable "run_id" { type = string }
variable "vpc_id" { type = string }

variable "catalog_path" {
  type    = string
  default = "fixtures/rules.csv"
}
