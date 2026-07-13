variable "name" {
  type = string
}

variable "port" {
  type = number
}

variable "owner" {
  type = string
}

variable "tier" {
  type = string
}

variable "healthcheck" {
  type     = string
  default  = null
  nullable = true
}

variable "environment" {
  type = string
}

variable "tags" {
  type = map(string)
}
