resource "aws_instance" "instances" {
  for_each      = toset(data.aws_subnets.random.ids)
  subnet_id     = each.value
  ami           = "ami-00000000000000000"
  instance_type = "t2.micro"
}