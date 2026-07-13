variable "name_prefix" {
  type        = string
  description = "唯一的小写资源名前缀。"
  default     = "tfpro-c21"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{2,30}$", var.name_prefix))
    error_message = "name_prefix 必须是 3–31 位小写字母、数字或连字符。"
  }
}

variable "run_id" {
  type        = string
  description = "用于精确识别和清理本次 grader 资源的唯一标记。"
  default     = "manual"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{2,39}$", var.run_id))
    error_message = "run_id 必须是 3–40 位小写字母、数字或连字符。"
  }
}

variable "aws_region" {
  type        = string
  description = "LocalStack 使用的 AWS 区域。"
  default     = "us-east-1"
}

variable "localstack_endpoint" {
  type        = string
  description = "LocalStack edge endpoint。"
  default     = "http://localhost:4566"

  validation {
    condition     = can(regex("^https?://(localhost|127\\.0\\.0\\.1)(:[0-9]+)?/?$", var.localstack_endpoint))
    error_message = "localstack_endpoint 只能指向 localhost 或 127.0.0.1。"
  }
}

variable "environment" {
  type        = string
  description = "要实例化的环境。"
  default     = "prod"

  # TODO: 只允许 dev、stage、prod。
}

variable "rules_csv_path" {
  type        = string
  description = "安全规则 CSV 路径。"
  default     = "../fixtures/rules.csv"
}

variable "network" {
  description = "VPC 与 subnet 的强类型合同。"
  type = object({
    cidr_block = string
    subnets = map(object({
      cidr_block        = string
      availability_zone = string
      owner             = string
    }))
  })

  default = {
    cidr_block = "10.42.0.0/16"
    subnets = {
      public-a = {
        cidr_block        = "10.42.10.0/24"
        availability_zone = "us-east-1a"
        owner             = "edge"
      }
      private-a = {
        cidr_block        = "10.42.20.0/24"
        availability_zone = "us-east-1b"
        owner             = "platform"
      }
      data-a = {
        cidr_block        = "10.42.30.0/24"
        availability_zone = "us-east-1c"
        owner             = "data"
      }
    }
  }

  # TODO: 校验 VPC/subnet CIDR、非空 owner、非空 subnet 集合和 CIDR 唯一性。
}
