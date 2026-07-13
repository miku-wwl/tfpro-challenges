variable "catalog_file" {
  type    = string
  default = "../fixtures/services.json"
}

variable "environment" {
  type    = string
  default = "prod"

  # TODO: 只允许 dev、staging、prod。
}

