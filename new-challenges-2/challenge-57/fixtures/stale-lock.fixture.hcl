# Deliberately stale: the root module now requires the 5.100 patch line.
provider "registry.terraform.io/hashicorp/aws" {
  version     = "5.99.0"
  constraints = ">= 5.90.0, < 6.0.0"
  hashes = [
    "h1:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=",
  ]
}
