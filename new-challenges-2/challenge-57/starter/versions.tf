terraform {
  # TODO 1: constrain Terraform to the 1.6 line and the root AWS provider to
  # the required 5.100 patch line so the injected stale lock is rejected.
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.90.0, < 6.0.0"
    }
  }
}
