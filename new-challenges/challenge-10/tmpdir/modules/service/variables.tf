variable "service" {
  type = object({
    name        = string
    port        = number
    owner       = string
    tier        = string
    healthcheck = optional(string)
  })
}

variable "context" {
  type = object({
    environment = string
    tags        = map(string)
  })
}
