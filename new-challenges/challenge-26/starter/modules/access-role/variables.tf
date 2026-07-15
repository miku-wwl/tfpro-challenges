variable "name_prefix" {
  type = string
}

variable "environment" {
  type = string
}

variable "role_key" {
  type = string
}

variable "team" {
  type = string
}

variable "workload" {
  type = string
}

variable "actions" {
  type = list(string)
}

variable "resources" {
  type = list(string)
}
