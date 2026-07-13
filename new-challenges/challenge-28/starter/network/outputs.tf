# TODO: Publish both primary and dr locations.
output "network_contract" {
  value = {
    primary = {
      vpc_id    = aws_vpc.primary.id
      subnet_id = aws_subnet.primary.id
      region    = var.primary_region
    }
  }
}

