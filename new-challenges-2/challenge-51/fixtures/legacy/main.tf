data "aws_subnet" "target" { id = var.subnet_id }
data "aws_ami" "target" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = [var.ami_name_pattern]
  }
}
data "aws_iam_policy_document" "trust" {
  statement {
    sid     = "Ec2AssumeRole"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}
resource "aws_iam_role" "legacy" {
  name               = var.role_name
  assume_role_policy = data.aws_iam_policy_document.trust.json
  tags               = { Name = var.role_name, RunId = var.run_id, Workload = "api", ManagedBy = "terraform", Ownership = "takeover" }
}
resource "aws_iam_instance_profile" "legacy" {
  name = var.profile_name
  role = aws_iam_role.legacy.name
  tags = { Name = var.profile_name, RunId = var.run_id, Workload = "api", ManagedBy = "terraform", Ownership = "takeover" }
}
resource "aws_instance" "legacy" {
  ami                  = data.aws_ami.target.id
  instance_type        = "t3.micro"
  subnet_id            = data.aws_subnet.target.id
  iam_instance_profile = aws_iam_instance_profile.legacy.name
  tags                 = { Name = "${var.run_id}-api", RunId = var.run_id, Workload = "api", ManagedBy = "terraform", Ownership = "takeover" }
}
output "instance_id" { value = aws_instance.legacy.id }
output "ami_id" { value = data.aws_ami.target.id }
