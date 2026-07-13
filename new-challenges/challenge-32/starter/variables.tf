variable "name_prefix" {
  type        = string
  description = "本题资源名前缀。"
  default     = "tfpro-c32"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{2,30}$", var.name_prefix))
    error_message = "name_prefix 必须是 3–31 位小写字母、数字或连字符。"
  }
}

variable "run_id" {
  type        = string
  description = "grader 的唯一清理标记。"
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

variable "user_data_template_path" {
  type        = string
  description = "敏感启动脚本模板路径。"
  default     = "../fixtures/bootstrap.sh.tftpl"

  # TODO: 在 templatefile 之前拒绝不存在的模板。
}

variable "bootstrap" {
  description = "必须作为整体传播 sensitivity 的启动数据。"
  type = object({
    api_token         = string
    database_password = string
    feature_flags     = map(bool)
  })

  # TODO: 将整个复杂对象标记为 sensitive，并校验两个 secret 的最小长度。
  default = {
    api_token         = "local-only-api-token"
    database_password = "local-only-database-password"
    feature_flags = {
      metrics = true
      tracing = false
    }
  }
}

variable "identity_boundary" {
  description = "workload 可以读取的显式 SSM parameters。"
  type = object({
    role_path              = string
    allowed_parameter_arns = set(string)
  })

  default = {
    role_path = "/tfpro/"
    allowed_parameter_arns = [
      "arn:aws:ssm:us-east-1:000000000000:parameter/tfpro/api-token",
      "arn:aws:ssm:us-east-1:000000000000:parameter/tfpro/database-password"
    ]
  }

  validation {
    condition     = can(regex("^/[a-z0-9/-]+/$", var.identity_boundary.role_path))
    error_message = "role_path 必须是小写绝对 IAM path，并以 / 结尾。"
  }
}

