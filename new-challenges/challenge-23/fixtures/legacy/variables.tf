variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "localstack_endpoint" {
  type    = string
  default = "http://localhost:4566"
}

variable "name_prefix" {
  type = string
}

variable "network" {
  type = object({
    cidr_block = string
    subnets = map(object({
      cidr_block        = string
      availability_zone = string
      tier              = string
    }))
    security_groups = map(object({
      description = string
    }))
  })

  default = {
    cidr_block = "10.23.0.0/16"
    subnets = {
      app-a = {
        cidr_block        = "10.23.10.0/24"
        availability_zone = "us-east-1a"
        tier              = "app"
      }
      app-b = {
        cidr_block        = "10.23.20.0/24"
        availability_zone = "us-east-1b"
        tier              = "app"
      }
    }
    security_groups = {
      app = { description = "Application workload" }
      ops = { description = "Operations access" }
    }
  }
}
