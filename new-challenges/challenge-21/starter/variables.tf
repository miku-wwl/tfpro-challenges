variable "name_prefix" {
  type    = string
  default = "tfpro-c21"
  # TODO: validate a safe lowercase prefix.
}

variable "run_id" {
  type    = string
  default = "manual-c21"
  # TODO: validate a safe lowercase run identity.
}

variable "aws_region" {
  type    = string
  default = "us-east-1"
  # TODO: restrict this lab to us-east-1.
}

variable "localstack_endpoint" {
  type    = string
  default = "http://localhost:4566"
  # TODO: require a loopback root origin with an explicit valid port.
}

variable "environment" {
  type    = string
  default = "prod"
  # TODO: allow only dev, stage, prod.
}

variable "rules_csv_path" {
  type    = string
  default = "../fixtures/rules.csv"
}

variable "subnet_ids" {
  type        = map(string)
  description = "Existing subnet IDs keyed by public-a, private-a, and data-a."
  # TODO: require the exact three logical keys and syntactically valid IDs.
}
