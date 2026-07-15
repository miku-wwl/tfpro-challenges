variable "localstack_endpoint" { type = string }
variable "run_id" { type = string }
variable "vpc_id" { type = string }
variable "catalog_path" { type = string }

variable "aws_region" {
  type    = string
  default = "us-east-1"
}
