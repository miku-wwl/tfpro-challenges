variable "run_id" {
  type    = string
  default = "tfpro-c29"
  # TODO: Validate lowercase S3-safe run IDs.
}
variable "catalog_file" {
  type    = string
  default = "../fixtures/services.csv"
}
variable "target_environment" {
  type    = string
  default = "prod"
  # TODO: Allow only dev, stage, prod.
}
variable "primary_region" {
  type    = string
  default = "us-east-1"
}
variable "dr_region" {
  type    = string
  default = "us-west-2"
  # TODO: validate region syntax and add a cross-variable check that rejects primary_region.
}
variable "localstack_endpoint" {
  type    = string
  default = "http://localhost:4566"
  validation {
    condition     = can(regex("^http://(localhost|127\\.0\\.0\\.1):[0-9]+$", var.localstack_endpoint))
    error_message = "localstack_endpoint must be loopback."
  }
}

