# The starter middle module implicitly forwards the root default provider to
# both leaf modules. Task 3 declares two aliases and maps them explicitly.

variable "primary_bucket_name" {
  description = "Primary release bucket name."
  type        = string
}

variable "audit_bucket_name" {
  description = "Audit release bucket name."
  type        = string
}

module "primary" {
  source      = "../release"
  bucket_name = var.primary_bucket_name
}

module "audit" {
  source      = "../release"
  bucket_name = var.audit_bucket_name
}

output "bucket_names" {
  description = "Names returned by the two leaf module instances."
  value = {
    primary = module.primary.bucket_name
    audit   = module.audit.bucket_name
  }
}
