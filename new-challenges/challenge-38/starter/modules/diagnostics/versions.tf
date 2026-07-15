terraform {
  required_version = "~> 1.6"

  required_providers {
    aws = {
      source = "hashicorp/aws"
      # TODO: 约束必须与 root 相交，并声明 aws.dr configuration_aliases。
    }
  }
}

