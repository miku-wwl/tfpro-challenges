variable "run_id" { type = string }
variable "role" { type = string }
variable "services" {
  type = map(object({
    name           = string
    owner          = string
    environment    = string
    retention_days = number
    enabled        = bool
  }))
}
variable "peer_topics" { type = map(string) }

