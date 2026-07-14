resource "aws_instance" "instances" {
  for_each = toset(var.subnet_ids)

  subnet_id     = each.value
  ami           = var.ami
  instance_type = var.instance_type
}