variable "run_id" {
  type        = string
  description = "本次运行时发布的隔离标识。"
  default     = "tfpro-c40"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{4,20}[a-z0-9]$", var.run_id))
    error_message = "run_id must be 6-22 lowercase letters, digits, or hyphens."
  }
}

variable "primary_region" {
  type    = string
  default = "us-east-1"
}

variable "dr_region" {
  type    = string
  default = "us-west-2"

  validation {
    condition     = var.dr_region != var.primary_region
    error_message = "dr_region must differ from primary_region."
  }
}

variable "localstack_endpoint" {
  type        = string
  description = "LocalStack loopback edge endpoint。"
  default     = "http://localhost:4566"

  validation {
    condition = (
      can(regex("^https?://(localhost|127\\.0\\.0\\.1|\\[::1\\]):([1-9][0-9]{0,4})\\z", var.localstack_endpoint)) &&
      try(tonumber(regex("^https?://(localhost|127\\.0\\.0\\.1|\\[::1\\]):([1-9][0-9]{0,4})\\z", var.localstack_endpoint)[1]) <= 65535, false)
    )
    error_message = "localstack_endpoint must be a loopback HTTP(S) origin with an explicit port from 1 to 65535."
  }
}

variable "artifact_state_path" {
  type        = string
  description = "相对 runtime root 的 artifact local state 路径。"
  default     = "../artifact/terraform.tfstate"
}

variable "runtime_catalog_path" {
  type        = string
  description = "相对 runtime root 的运行时目录 JSON。"
  default     = "../../fixtures/runtime.json"
}
