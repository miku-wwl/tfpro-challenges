variable "service" {
  type = object({
    name  = string
    port  = number
    owner = string
    tier  = string
  })
}

variable "environment" {
  type = string
}

variable "common_tags" {
  type = map(string)
}

