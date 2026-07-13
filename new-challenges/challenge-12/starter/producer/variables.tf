variable "environment" {
  type    = string
  default = "prod"
}

variable "services_file" {
  type    = string
  default = "../../fixtures/services.csv"
}
