variable "service_name" {
  type    = string
  default = "checkout-api"
}

variable "release_channels" {
  type    = set(string)
  default = ["canary", "stable"]
}
