variable "catalog" {
  type = map(object({
    owner = string
    port  = number
    tier  = string
  }))

  default = {
    api    = { owner = "platform", port = 8080, tier = "critical" }
    web    = { owner = "experience", port = 3000, tier = "standard" }
    worker = { owner = "platform", port = 9090, tier = "standard" }
  }
}

variable "manifest_path" {
  type    = string
  default = "./generated/service-manifest.json"
}

variable "guardian_import_id" {
  type    = string
  default = "ops-guardian-v1"
}

