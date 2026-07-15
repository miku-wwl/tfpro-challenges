variable "bucket_name" { type = string }
variable "environment" { type = string }
variable "location" { type = string }
variable "platform_schema_version" { type = number }
variable "service" {
  type = object({ name = string, owner = string, tier = string, port = number })
}
