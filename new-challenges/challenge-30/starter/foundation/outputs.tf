output "network_contract" {
  value = {
    contract_version = 1
    primary = {
      region    = var.primary_region
      vpc_id    = aws_vpc.primary.id
      subnet_id = aws_subnet.primary.id
      cidr      = aws_vpc.primary.cidr_block
    }
    dr = {
      region    = var.dr_region
      vpc_id    = aws_vpc.dr.id
      subnet_id = aws_subnet.dr.id
      cidr      = aws_vpc.dr.cidr_block
    }
  }
}
