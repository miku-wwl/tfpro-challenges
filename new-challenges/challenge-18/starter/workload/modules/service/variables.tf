variable "deployment_key" {
  type = string
}

variable "service" {
  type = object({
    name        = string
    owner       = string
    environment = string
    port        = number
    enabled     = bool
    location    = string
    tier        = string
  })
}

variable "network" {
  type = object({
    vpc_id    = string
    subnet_id = string
    region    = string
  })
}

