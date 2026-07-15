variable "run_id" { type = string }
variable "service" {
  type = object({
    name    = string
    owner   = string
    enabled = bool
  })
}
