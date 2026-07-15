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
variable "run_id" { type = string }
variable "primary_subnet_id" { type = string }
variable "dr_subnet_id" { type = string }
variable "catalog_path" {
  type    = string
  default = "fixtures/regions.json"
}
