variable "run_id" { type = string }
variable "routes" {
  type = map(object({
    name          = string
    bucket_suffix = string
    role_suffix   = string
    enabled       = bool
  }))
}
