resource "aws_vpc" "primary" {
  cidr_block = "10.28.0.0/16"
  tags       = { Name = "${var.run_id}-primary" }
}

# TODO: Route both DR resources through aws.dr.
resource "aws_vpc" "dr" {
  cidr_block = "10.29.0.0/16"
  tags       = { Name = "${var.run_id}-dr" }
}

resource "aws_subnet" "primary" {
  vpc_id     = aws_vpc.primary.id
  cidr_block = "10.28.1.0/24"
  tags       = { Name = "${var.run_id}-primary-app" }
}

resource "aws_subnet" "dr" {
  vpc_id     = aws_vpc.dr.id
  cidr_block = "10.29.1.0/24"
  tags       = { Name = "${var.run_id}-dr-app" }
}

