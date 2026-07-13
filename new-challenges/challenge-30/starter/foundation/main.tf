resource "aws_vpc" "primary" {
  cidr_block           = "10.30.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = { Name = "${var.run_id}-primary" }
}

resource "aws_subnet" "primary" {
  vpc_id     = aws_vpc.primary.id
  cidr_block = "10.30.1.0/24"
  tags       = { Name = "${var.run_id}-primary" }
}

resource "aws_vpc" "dr" {
  # TODO: Route DR resources through the DR provider alias.
  cidr_block           = "10.31.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = { Name = "${var.run_id}-dr" }
}

resource "aws_subnet" "dr" {
  vpc_id     = aws_vpc.dr.id
  cidr_block = "10.31.1.0/24"
  tags       = { Name = "${var.run_id}-dr" }
}
