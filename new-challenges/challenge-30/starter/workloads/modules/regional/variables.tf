variable "bucket" { type = string }
variable "location" { type = string }
variable "run_id" { type = string }
variable "workloads" { type = map(any) }
variable "identity_contract" { type = any }
variable "platform_contract" { type = any }
