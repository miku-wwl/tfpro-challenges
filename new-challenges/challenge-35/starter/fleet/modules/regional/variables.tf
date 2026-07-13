variable "run_id" { type = string }
variable "role" { type = string }
variable "ami_id" { type = string }
variable "subnet_id" { type = string }
variable "security_group_id" { type = string }
variable "instance_profile_name" { type = string }
variable "fleets" {
  type = map(object({
    name     = string, environment = string, location = string, instance_type = string,
    min_size = number, max_size = number, desired_capacity = number,
    owner    = string, enabled = bool, key = string
  }))
}
