terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.80.0"
    }
  }
}

resource "aws_launch_template" "this" {
  name          = var.name
  image_id      = var.image_id
  instance_type = var.instance_type
}

# LocalStack Community does not include Auto Scaling. This resource represents
# ASG desired capacity for the lifecycle/ignore_changes exercise in Task 5.
resource "terraform_data" "desired_capacity" {
  input = 2
  lifecycle {
    ignore_changes = [input]
  }
}