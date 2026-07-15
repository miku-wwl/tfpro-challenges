variable "run_id" { type = string }
variable "role" { type = string }
variable "ami_id" { type = string }
variable "instance_profile" { type = string }
variable "network" {
  type = object({ subnet_id = string, security_group_id = string })
}
variable "fleets" {
  type = map(object({
    name          = string
    environment   = string
    location      = string
    instance_type = string
    owner         = string
    enabled       = bool
    key           = string
  }))
}
