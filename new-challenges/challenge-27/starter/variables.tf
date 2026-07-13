variable "aws_region" {
  type        = string
  description = "LocalStack 使用的 AWS 区域"
  default     = "us-east-1"
}

variable "localstack_endpoint" {
  type        = string
  description = "LocalStack edge endpoint"
  default     = "http://localhost:4566"
}

variable "name_prefix" {
  type    = string
  default = "tfpro-c27"
}

variable "application" {
  type    = string
  default = "orders-api"
}

variable "environment" {
  type    = string
  default = "dev"
}

variable "release_version" {
  type    = string
  default = "1.0.0"
  # TODO: 验证严格 SemVer。
}

variable "manifest_path" {
  type    = string
  default = "../fixtures/release-v1.json"
}

