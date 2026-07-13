variable "name_prefix" {
  type        = string
  description = "资源名前缀。"
  default     = "tfpro-c31"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{2,30}$", var.name_prefix))
    error_message = "name_prefix 必须是 3–31 位小写字母、数字或连字符。"
  }
}

variable "run_id" {
  type        = string
  description = "grader 用于精确清理资源的唯一标记。"
  default     = "manual"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{2,39}$", var.run_id))
    error_message = "run_id 必须是 3–40 位小写字母、数字或连字符。"
  }
}

variable "aws_region" {
  type        = string
  description = "LocalStack region。"
  default     = "us-east-1"
}

variable "localstack_endpoint" {
  type        = string
  description = "LocalStack edge endpoint。"
  default     = "http://localhost:4566"

  validation {
    condition     = can(regex("^https?://(localhost|127\\.0\\.0\\.1|\\[::1\\])(:[0-9]+)?/?$", var.localstack_endpoint))
    error_message = "localstack_endpoint 只能是 loopback HTTP(S) 根地址。"
  }
}

variable "environment" {
  type        = string
  description = "目标部署环境。"
  default     = "prod"

  # TODO: 只允许 dev、stage、prod。
}

variable "fleet_csv_path" {
  type        = string
  description = "计算舰队 CSV 路径。"
  default     = "../fixtures/fleets.csv"

  # TODO: 在解码前拒绝不存在的文件。
}

variable "network" {
  description = "VPC 与 subnet 合同。"
  type = object({
    cidr_block = string
    subnets = map(object({
      cidr_block        = string
      availability_zone = string
      owner             = string
    }))
  })

  default = {
    cidr_block = "10.61.0.0/16"
    subnets = {
      public-a = {
        cidr_block        = "10.61.10.0/24"
        availability_zone = "us-east-1a"
        owner             = "edge"
      }
      private-a = {
        cidr_block        = "10.61.20.0/24"
        availability_zone = "us-east-1b"
        owner             = "platform"
      }
    }
  }

  # TODO: 校验合法且唯一的 CIDR、非空 AZ/owner 与非空 subnet 集合。
}

