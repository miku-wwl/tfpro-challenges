variable "environment" {
  type    = string
  default = "training"
}

variable "release_id" {
  type        = string
  description = "发布流水线注入的不可歧义版本"
  default     = "v1"
}

variable "services" {
  type        = set(string)
  description = "发布给 consumer 的服务集合"
  default     = ["worker", "api"]
}
