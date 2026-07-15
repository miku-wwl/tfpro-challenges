variable "fleets" {
  type = map(object({ name = string, location = string, release = string, capacity = number, instance_type = string, artifact_sha256 = string, fields = list(string), fleet_key = string }))
}
variable "location" { type = string }
variable "region" { type = string }
variable "run_id" { type = string }
variable "subnet_id" { type = string }
variable "image_id" { type = string }
variable "instance_profile_name" { type = string }
