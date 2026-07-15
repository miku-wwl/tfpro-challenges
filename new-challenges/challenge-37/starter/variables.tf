variable "aws_region" {
  type        = string
  description = "LocalStack 使用的 AWS 区域"
  default     = "us-east-1"
}

variable "localstack_endpoint" {
  type        = string
  description = "LocalStack edge endpoint"
  default     = "http://localhost:4566"
  validation {
    condition     = can(regex("^https?://(localhost|127\\.0\\.0\\.1|\\[::1\\])(:[0-9]{1,5})?/?\\z", var.localstack_endpoint))
    error_message = "localstack_endpoint 必须是 loopback HTTP(S) 根地址。"
  }
}

variable "name_prefix" {
  type        = string
  description = "资源名称前缀"
  default     = "tfpro-c37-lab"
  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{2,30}$", var.name_prefix))
    error_message = "name_prefix 只能包含小写字母、数字和连字符。"
  }
}

variable "run_id" {
  type        = string
  description = "grader 隔离标识"
  default     = "manual-c37"
}

variable "vpc_cidr" {
  type        = string
  description = "规则 VPC CIDR"
  default     = "10.137.0.0/16"
  validation {
    condition     = can(cidrnetmask(var.vpc_cidr))
    error_message = "vpc_cidr 必须是有效 IPv4 CIDR。"
  }
}

variable "rules_csv_path" {
  type        = string
  description = "Security Group rules CSV 路径"
  default     = "../fixtures/rules.csv"
  validation {
    condition     = fileexists(var.rules_csv_path) && can(csvdecode(file(var.rules_csv_path)))
    error_message = "rules_csv_path 必须指向可解析的 CSV。"
  }
}
