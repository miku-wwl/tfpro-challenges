variable "aws_region" {
  type    = string
  default = "us-east-1"
}
variable "localstack_endpoint" {
  type    = string
  default = "http://localhost:4566"
}
variable "run_id" { type = string }
variable "policy_json" {
  type      = string
  sensitive = true
}
