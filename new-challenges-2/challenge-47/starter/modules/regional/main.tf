data "aws_caller_identity" "current" {}

data "aws_ami" "selected" {
  most_recent = true
  owners      = ["self"]
  filter {
    name   = "name"
    values = [var.image_name]
  }
}

data "aws_subnet" "selected" {
  id = var.subnet_id
}

resource "aws_instance" "node" {
  ami                  = data.aws_ami.selected.id
  instance_type        = var.instance_type
  subnet_id            = data.aws_subnet.selected.id
  iam_instance_profile = var.iam_instance_profile

  tags = merge(var.common_tags, {
    Name   = "tfpro-c47-${var.run_id}-${var.route}"
    Route  = var.route
    Region = var.region
    RunId  = var.run_id
    AmiId  = data.aws_ami.selected.id
    Owner  = var.owner
  })

  lifecycle {
    precondition {
      condition = (
        can(regex("^[0-9]{12}$", data.aws_caller_identity.current.account_id)) &&
        can(regex("^ami-[0-9a-f]{8,17}$", data.aws_ami.selected.id)) &&
        data.aws_subnet.selected.id == var.subnet_id
      )
      error_message = "The routed account, AMI, or injected subnet contract is invalid."
    }
  }
}
