variable "run_id" {
  type = string
}

variable "target_environment" {
  type    = string
  default = "prod"
  # TODO: allow only dev, stage, prod.
}

variable "catalog_file" {
  type    = string
  default = "../fixtures/applications.csv"
}

variable "state_bucket" {
  type = string
}

variable "foundation_state_key" {
  type    = string
  default = "foundation/terraform.tfstate"
}

variable "expected_platform_revision" {
  type = number
}

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
