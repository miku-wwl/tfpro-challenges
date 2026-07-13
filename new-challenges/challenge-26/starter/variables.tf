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
    condition     = startswith(var.localstack_endpoint, "http://")
    error_message = "endpoint 必须使用 HTTP。"
  }
}

variable "name_prefix" {
  type        = string
  description = "资源唯一前缀"
  default     = "tfpro-c26"
}

variable "environment" {
  type        = string
  description = "部署环境"
  default     = "dev"

  # TODO: 只接受 dev、stage、prod。
}

variable "catalog_path" {
  type        = string
  description = "IAM 身份 CSV 路径"
  default     = "../fixtures/access-catalog.csv"
}

variable "policy_catalog_path" {
  type        = string
  description = "策略 JSON 路径"
  default     = "../fixtures/policy-catalog.json"
}

