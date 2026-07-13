variable "run_id" { type = string }
variable "deployment_key" { type = string }
variable "application" {
  type = object({
    name        = string
    owner       = string
    environment = string
    port        = number
    enabled     = bool
    location    = string
  })
}
variable "network" {
  type = object({
    vpc_id    = string
    subnet_id = string
    region    = string
  })
}

