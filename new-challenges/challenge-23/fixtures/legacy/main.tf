locals {
  subnet_names         = sort(keys(var.network.subnets))
  security_group_names = sort(keys(var.network.security_groups))
}

resource "aws_vpc" "main" {
  count = 1

  cidr_block           = var.network.cidr_block
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name      = "${var.name_prefix}-vpc"
    ManagedBy = "terraform"
  }
}

resource "aws_subnet" "this" {
  count = length(local.subnet_names)

  vpc_id            = aws_vpc.main[0].id
  cidr_block        = var.network.subnets[local.subnet_names[count.index]].cidr_block
  availability_zone = var.network.subnets[local.subnet_names[count.index]].availability_zone

  tags = {
    Name      = "${var.name_prefix}-${local.subnet_names[count.index]}"
    Tier      = var.network.subnets[local.subnet_names[count.index]].tier
    ManagedBy = "terraform"
  }
}

resource "aws_security_group" "this" {
  count = length(local.security_group_names)

  name        = "${var.name_prefix}-${local.security_group_names[count.index]}"
  description = var.network.security_groups[local.security_group_names[count.index]].description
  vpc_id      = aws_vpc.main[0].id

  tags = {
    Name      = "${var.name_prefix}-${local.security_group_names[count.index]}"
    ManagedBy = "terraform"
  }
}
