data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["000000000000"]

  filter {
    name   = "image-id"
    values = ["ami-6233d274fe437734e"]
  }
}


resource "aws_instance" "this" {
  ami                  = data.aws_ami.amazon_linux.id
  instance_type        = var.instance_type
  iam_instance_profile = var.iam_instance_profile
}