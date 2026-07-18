variable "resource_name" {
  description = "Name shared by the Launch Template and Auto Scaling Group. Override only for isolated verification copies."
  type        = string
  default     = "tfpro-c82-release"

  validation {
    condition     = can(regex("^tfpro-c82-[a-z0-9-]+$", var.resource_name))
    error_message = "resource_name must start with tfpro-c82- and contain only lowercase letters, digits, and hyphens."
  }
}

variable "block_devices" {
  type = map(object({
    volume_type           = string
    volume_size           = number
    encrypted             = bool
    delete_on_termination = bool
    iops                  = optional(number)
    throughput            = optional(number)
    }
  ))

  default = {
    "/dev/sda1" : {
      volume_type           = "gp3"
      volume_size           = 8
      encrypted             = true
      delete_on_termination = true
      iops                  = 3000
      throughput            = 125
    }

    "/dev/sdf" : {
      volume_type           = "gp3"
      volume_size           = 20
      encrypted             = true
      delete_on_termination = true
      iops                  = 3000
      throughput            = 125
    }
  }

  validation {
    condition     = alltrue([for k in keys(var.block_devices) : startswith(k, "/dev/")])
    error_message = "Every device key must start with /dev/."
  }

  validation {
    condition     = alltrue([for v in values(var.block_devices) : v.volume_size > 0])
    error_message = "Every volume_size must be greater than 0."
  }

  validation {
    condition     = alltrue([for v in values(var.block_devices) : v.volume_type == "gp3"])
    error_message = "Every volume_type must be gp3."
  }

  validation {
    condition = alltrue([
      for v in values(var.block_devices) : v.iops == null || v.iops >= 3000
    ])
    error_message = "When iops is set, it must be at least 3000."
  }

  validation {
    condition = alltrue([
      for v in values(var.block_devices) : v.throughput == null || v.throughput >= 125
    ])
    error_message = "When throughput is set, it must be at least 125."
  }
}
