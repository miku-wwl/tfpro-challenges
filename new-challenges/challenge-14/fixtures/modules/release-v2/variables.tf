variable "service_name" {
  type = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]+$", var.service_name))
    error_message = "service_name must be a lowercase slug."
  }
}

variable "release_channels" {
  type = set(string)

  validation {
    condition     = length(var.release_channels) > 0 && alltrue([for channel in var.release_channels : contains(["canary", "stable"], channel)])
    error_message = "release_channels must contain canary and/or stable."
  }
}
