variable "run_id" {
  type = string
}

variable "role" {
  type = string
}

variable "deployments" {
  type = map(object({
    name        = string
    owner       = string
    environment = string
    locations   = list(string)
    location    = string
    port        = number
    enabled     = bool
  }))
}

variable "network_contract" {
  type = object({
    region    = string
    vpc_id    = string
    subnet_id = string
    cidr      = string
  })
}

variable "platform_contract" {
  type = object({
    region     = string
    sg_id      = string
    topic_arn  = string
    table_name = string
  })
}
