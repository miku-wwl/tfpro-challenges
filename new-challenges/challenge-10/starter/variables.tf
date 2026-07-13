variable "services" {
  # TODO: v2 root contract 应改为以服务名为 key 的 map。
  type = list(object({
    name        = string
    port        = number
    owner       = string
    tier        = string
    healthcheck = optional(string)
  }))

  default = [
    { name = "api", port = 8080, owner = "platform", tier = "critical", healthcheck = "/ready" },
    { name = "web", port = 3000, owner = "experience", tier = "standard" },
    { name = "worker", port = 9090, owner = "platform", tier = "standard" }
  ]
}

variable "environment" {
  type    = string
  default = "prod"
}

variable "common_tags" {
  type = map(string)
  default = {
    managed_by  = "terraform"
    cost_center = "platform"
  }
}
