# TODO(1): normalize and independently validate both service and node catalogs.
locals {
  raw           = jsondecode(file(var.catalog_path))
  services      = {}
  nodes         = {}
  catalog_valid = false
}

data "aws_subnet" "target" { id = var.subnet_id }
data "aws_ami" "release" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = [var.ami_name_pattern]
  }
}

# TODO(2): create the real SG, service-keyed launch templates, and node-keyed EC2 fleet.
# TODO(3): enforce the raw-vs-base64 user-data contract and create-before-destroy rollout.
