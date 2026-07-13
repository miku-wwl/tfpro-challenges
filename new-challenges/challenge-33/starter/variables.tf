variable "aws_region" {
  type        = string
  description = "LocalStack 使用的 AWS 区域。"
  default     = "us-east-1"
}

variable "localstack_endpoint" {
  type        = string
  description = "LocalStack edge endpoint。"
  default     = "http://localhost:4566"
}

variable "name_prefix" {
  type        = string
  description = "资源名前缀。"
  default     = "tfpro-c33"
}

variable "run_id" {
  type        = string
  description = "并发验收隔离标识。"
  default     = "lab"
}

variable "catalog_file" {
  type        = string
  description = "服务 CSV 路径。"
  default     = "fixtures/services.csv"
}
