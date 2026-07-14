
variable "environement" {
  type = string
}

variable "s3_buckets" {
  type = list(string)
}

variable "s3_base_object" {}

variable "org-name" {}

variable "pet_id" {
  type = string
}

variable "region" {
  type = string
}

variable "localstack_endpoint" {
  type    = string
  default = "http://localhost:4566"
}

variable "sg_name" {}
