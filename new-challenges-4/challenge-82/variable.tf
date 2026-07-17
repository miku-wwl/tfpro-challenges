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
  }

  validation {
    condition     = alltrue([for k in keys(var.block_devices) : startswith(k, "/dev/")])
    error_message = "device key must start with `/dev/`"
  }

  validation {
    condition     = alltrue([for v in values(var.block_devices) : v.volume_size > 0])
    error_message = "volume size must more than 0"
  }

  validation {
    condition     = alltrue([for v in values(var.block_devices) : v.volume_type == "gp3"])
    error_message = "volume type must be gp3"
  }

  validation {
    condition = alltrue([
      for v in values(var.block_devices) : v.iops == null || v.iops >= 3000
    ])
    error_message = "if iops exists, it must be more than 3000"
  }

  validation {
    condition = alltrue([
      for v in values(var.block_devices) : v.throughput == null || v.throughput >= 125
    ])
    error_message = "if throughput exists, it must be more than 125"
  }
}