terraform {
  required_version = "~> 1.6"

  required_providers {
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6.0" # TODO: v2 requires the 3.7 patch line.
    }
  }
}
