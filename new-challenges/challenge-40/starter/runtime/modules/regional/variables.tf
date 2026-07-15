variable "run_id" {
  type = string
}

variable "role" {
  type = string
}

variable "region" {
  type = string
}

variable "ami_id" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "subnet_id" {
  type = string
}

variable "instance_profile_name" {
  type = string
}

variable "fleets" {
  type = map(object({
    name          = string
    location      = string
    artifact      = string
    instance_type = string
    replicas      = number
    key           = string
  }))
}

variable "release_contract" {
  type = object({
    contract_version = number
    release_version  = string
    bucket_name      = string
    region           = string
    artifacts = map(object({
      key    = string
      sha256 = string
    }))
  })
}
