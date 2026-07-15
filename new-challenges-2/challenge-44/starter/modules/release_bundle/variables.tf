variable "run_id" { type = string }
variable "name" { type = string }
variable "owner" { type = string }
variable "contract" {
  type = object({
    interface_version = number
    artifact          = object({ key = string, payload = string, sha256 = string })
    identity          = object({ actions = list(string), raw_actions = list(string) })
  })
}
