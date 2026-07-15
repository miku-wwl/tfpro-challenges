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
  description = "S3 bucket 名称前缀"
  default     = "tfpro-c36-lab"
  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{2,30}$", var.name_prefix))
    error_message = "name_prefix 只能包含小写字母、数字和连字符。"
  }
}

variable "release_id" {
  type        = string
  description = "不可变发布标识"
  default     = "release-2026-07"
  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{2,31}$", var.release_id))
    error_message = "release_id 格式非法。"
  }
}

variable "run_id" {
  type        = string
  description = "grader 隔离标识"
  default     = "manual-c36"
}

variable "manifest_path" {
  type        = string
  description = "JSON artifact manifest 路径"
  default     = "../fixtures/manifest.json"
  validation {
    condition     = fileexists(var.manifest_path) && can(jsondecode(file(var.manifest_path)))
    error_message = "manifest_path 必须指向可解析的 JSON 文件。"
  }
}

variable "artifact_root" {
  type        = string
  description = "manifest source 的根目录"
  default     = "../fixtures"
  validation {
    condition     = fileexists("${var.artifact_root}/manifest.json")
    error_message = "artifact_root 必须指向 fixtures 根目录。"
  }
}
