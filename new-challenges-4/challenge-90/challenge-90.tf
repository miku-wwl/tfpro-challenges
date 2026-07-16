terraform {

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.80.0"
    }
  }
}

provider "aws" {
  region                      = "us-east-1"
  access_key                  = "test"
  secret_key                  = "test"
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true

  endpoints {
    ec2 = "http://localhost:4566"
    iam = "http://localhost:4566"
    sts = "http://localhost:4566"
  }
}

data "aws_iam_policy_document" "trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "read_artifacts" {
  statement {
    sid       = "ReadChallengeArtifacts"
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["arn:aws:s3:::tfpro-challenge90-artifacts/*"]
  }
}

resource "aws_iam_role" "workload" {
  name               = "TfProChallenge90Workload"
  assume_role_policy = data.aws_iam_policy_document.trust.json

  tags = {
    Challenge = "90"
  }
}

resource "aws_iam_policy" "read_artifacts" {
  name   = "TfProChallenge90ReadArtifacts"
  policy = data.aws_iam_policy_document.read_artifacts.json
}

resource "aws_iam_role_policy_attachment" "workload" {
  role       = aws_iam_role.workload.name
  policy_arn = aws_iam_policy.read_artifacts.arn
}

resource "aws_iam_instance_profile" "workload" {
  name = "TfProChallenge90Workload"
  role = aws_iam_role.workload.name
}

resource "aws_launch_template" "workload" {
  name          = "tfpro-challenge90-workload"
  image_id      = "ami-04681a1dbd79675a5"
  instance_type = "t2.micro"

  iam_instance_profile {
    name = aws_iam_instance_profile.workload.name
  }

  # Task 3 adds exactly one explicit business dependency here. The profile
  # reference does not prove that the separate policy attachment is ready.
}

resource "aws_instance" "workload" {
  ami                  = aws_launch_template.workload.image_id
  instance_type        = aws_launch_template.workload.instance_type
  iam_instance_profile = aws_iam_instance_profile.workload.name

  tags = {
    Name             = "tfpro-challenge90-workload"
    Challenge        = "90"
    LaunchTemplateId = aws_launch_template.workload.id
  }
}

output "delivery_contract" {
  value = {
    role             = aws_iam_role.workload.name
    policy_arn       = aws_iam_policy.read_artifacts.arn
    instance_profile = aws_iam_instance_profile.workload.name
    launch_template  = aws_launch_template.workload.id
    instance_id      = aws_instance.workload.id
  }
}
