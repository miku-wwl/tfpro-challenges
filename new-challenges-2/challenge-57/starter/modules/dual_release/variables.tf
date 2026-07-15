variable "run_id" {
  type = string
}

variable "release" {
  type = object({
    name       = string
    owner      = string
    object_key = string
    payload    = string
  })
}
