resource "aws_vpc" "primary" {
  cidr_block = "10.10.0.0/16"
  tags       = { Name = "tfpro-primary" }
}

# TODO: This recovery VPC is accidentally using the default provider.
resource "aws_vpc" "dr" {
  cidr_block = "10.20.0.0/16"
  tags       = { Name = "tfpro-dr" }
}

resource "aws_subnet" "primary" {
  vpc_id     = aws_vpc.primary.id
  cidr_block = "10.10.1.0/24"
  tags       = { Name = "tfpro-primary-app" }
}

# TODO: Keep the DR subnet in the same provider graph as the DR VPC.
resource "aws_subnet" "dr" {
  vpc_id     = aws_vpc.dr.id
  cidr_block = "10.20.1.0/24"
  tags       = { Name = "tfpro-dr-app" }
}

