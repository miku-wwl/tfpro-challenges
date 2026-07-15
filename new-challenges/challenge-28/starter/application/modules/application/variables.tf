variable "run_id" {
  type = string
}

variable "location" {
  type = string
}

variable "region" {
  type = string
}

variable "platform_bucket" {
  type = string
}

variable "platform_revision" {
  type = number
}

variable "applications" {
  type = map(object({
    name        = string
    owner       = string
    environment = string
    port        = number
    location    = string
  }))
}
