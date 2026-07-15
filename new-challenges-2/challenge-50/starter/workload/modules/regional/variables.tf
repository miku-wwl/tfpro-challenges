variable "run_id" {
  type = string
}

variable "location" {
  type = string
}

variable "region" {
  type = string
}

variable "image_id" {
  type = string
}

variable "subnet_id" {
  type = string
}

variable "instance_profile_name" {
  type = string
}

variable "fleets" {
  type = map(object({
    name          = string
    location      = string
    instance_type = string
    capacity      = number
    fields        = list(string)
    key           = string
  }))
}

variable "platform_contract" {
  type = any
}
