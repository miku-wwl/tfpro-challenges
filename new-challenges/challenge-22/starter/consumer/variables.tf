variable "state_bucket" { type = string }
variable "producer_state_key" { type = string }
variable "aws_region" { type = string }

variable "localstack_endpoint" {
  type    = string
  default = "http://localhost:4566"
}
