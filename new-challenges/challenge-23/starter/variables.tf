variable "aws_region" {
  type        = string
  description = "LocalStack 使用的 AWS 区域"
  default     = "us-east-1"
}

variable "localstack_endpoint" {
  type        = string
  description = "LocalStack edge endpoint；只允许 loopback"
  default     = "http://localhost:4566"

  validation {
    condition = can(regex(
      "^https?://(localhost|127\\.0\\.0\\.1|\\[::1\\])(:[0-9]+)?/?$",
      var.localstack_endpoint,
    ))
    error_message = "localstack_endpoint 必须是 localhost、127.0.0.1 或 [::1]。"
  }
}

variable "name_prefix" {
  type        = string
  description = "资源名称前缀；grader 会注入唯一值"
  default     = "tfpro-c23"
}

variable "network" {
  description = "待迁移的稳定网络合同"
  type = object({
    cidr_block = string
    subnets = map(object({
      cidr_block        = string
      availability_zone = string
      tier              = string
    }))
    security_groups = map(object({
      description = string
    }))
  })

  default = {
    cidr_block = "10.23.0.0/16"
    subnets = {
      app-a = {
        cidr_block        = "10.23.10.0/24"
        availability_zone = "us-east-1a"
        tier              = "app"
      }
      app-b = {
        cidr_block        = "10.23.20.0/24"
        availability_zone = "us-east-1b"
        tier              = "app"
      }
    }
    security_groups = {
      app = { description = "Application workload" }
      ops = { description = "Operations access" }
    }
  }
}
