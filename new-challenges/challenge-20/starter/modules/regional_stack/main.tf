data "aws_region" "current" {
  provider = aws.target
}

module "storage" {
  source = "../storage"

  providers = {
    aws.target = aws.target
  }

  bucket_name = "${var.name_prefix}-${var.role}"
  role        = var.role
}

resource "aws_sns_topic" "events" {
  provider = aws.target
  name     = "${var.name_prefix}-${var.role}-events"

  tags = {
    ManagedBy = "terraform"
    Role      = var.role
  }
}

check "provider_region" {
  assert {
    condition     = data.aws_region.current.name == var.expected_region
    error_message = "aws.target is mapped to the wrong root provider"
  }
}

