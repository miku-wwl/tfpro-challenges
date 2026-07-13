variable "run_id" { type = string }
variable "services" {
  type = map(object({
    name           = string
    owner          = string
    environment    = string
    retention_days = number
    enabled        = bool
  }))
}

