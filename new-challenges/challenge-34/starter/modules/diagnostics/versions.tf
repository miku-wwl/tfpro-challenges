terraform {
  required_version = "~> 1.6"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.100"
      # TODO: 声明 aws.primary 与 aws.dr configuration_aliases。
    }
  }
}
