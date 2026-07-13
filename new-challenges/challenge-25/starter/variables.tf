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
  type        = string
  description = "唯一资源前缀"
  default     = "tfpro-c25"
}

variable "application" {
  type    = string
  default = "checkout"
}

variable "environment" {
  type    = string
  default = "dev"
  # TODO: 只接受 dev、stage、prod。
}

variable "config_version" {
  type    = number
  default = 1
  # TODO: 必须为正整数。
}

variable "config_path" {
  type        = string
  description = "配置 JSON 路径"
  default     = "../fixtures/config-v1.json"
}

