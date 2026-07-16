terraform {
  required_version = "~> 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.80.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "3.6.3"
    }
  }
}

provider "aws" {
  region                      = "us-east-1"
  access_key                  = "test"
  secret_key                  = "test"
  s3_use_path_style           = true
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true

  endpoints {
    iam = "http://localhost:4566"
    s3  = "http://localhost:4566"
  }
}

variable "release_id" {
  description = "Release identifier advanced from v1 to v2 during Task 3."
  type        = string
  default     = "v1"
}

variable "role_revision" {
  description = "Role revision advanced from v1 to v2 during Task 2."
  type        = string
  default     = "v1"
}

resource "random_integer" "release" {
  min = 100000
  max = 999999

  keepers = {
    release_id = var.release_id
  }
}

resource "aws_s3_bucket" "releases" {
  bucket        = "tfpro-c65-lifecycle"
  force_destroy = true

  tags = {
    ManagedBy = "Terraform"
    Challenge = "65"
  }

  # Task 4 adds prevent_destroy. It is absent so the starter remains a normal
  # deployable and cleanable baseline.
}

data "aws_iam_policy_document" "assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "reader" {
  name               = "tfpro-c65-reader-${var.role_revision}"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json

  # Task 2 adds create_before_destroy before role_revision changes.
}

resource "aws_s3_object" "release" {
  bucket       = aws_s3_bucket.releases.id
  key          = "releases/current.json"
  content_type = "application/json"
  content = jsonencode({
    release_id = var.release_id
    serial     = random_integer.release.result
  })

  # Task 3 adds replace_triggered_by so a random_integer replacement forces an
  # explicit replacement of this object instead of an in-place update.
}

output "release_contract" {
  description = "Values used to compare the v1 baseline with the completed v2 state."
  value = {
    bucket     = aws_s3_bucket.releases.bucket
    object_key = aws_s3_object.release.key
    release_id = var.release_id
    role_name  = aws_iam_role.reader.name
    release_no = random_integer.release.result
  }
}
