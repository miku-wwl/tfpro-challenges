variable "target_environment" {
  type    = string
  default = "prod"

  validation {
    condition     = var.target_environment == "prod" || var.target_environment == "dev"
    error_message = "accept only dev or prod."
  }
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

  validation {
    condition     = var.policy.max_total_capacity > 0 && length(var.policy.allowed_tiers) > 0
    error_message = "a positive budget and a non-empty allowed tier set"
  }
}

variable "token_salt" {
  type      = string
  sensitive = true
  default   = "training-only-salt"
}
