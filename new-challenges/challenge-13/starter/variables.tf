variable "target_environment" {
  type    = string
  default = "prod"

  # TODO: accept only dev or prod.
}

variable "services_file" {
  type    = string
  default = "../fixtures/services.csv"
}

variable "owners_file" {
  type    = string
  default = "../fixtures/owners.json"
}

variable "policy" {
  type = object({
    allowed_tiers      = set(string)
    max_total_capacity = number
  })
  default = {
    allowed_tiers      = ["critical", "standard"]
    max_total_capacity = 10
  }

  # TODO: validate a positive budget and a non-empty allowed tier set.
}

variable "token_salt" {
  type      = string
  sensitive = true
  default   = "training-only-salt"
}
