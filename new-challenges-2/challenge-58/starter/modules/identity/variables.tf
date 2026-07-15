variable "run_id" {
  type = string
}

variable "identity" {
  type = object({
    name    = string
    owner   = string
    actions = list(string)
  })
}
