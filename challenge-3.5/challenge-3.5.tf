terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.80.0"
    }
    local = {
      source = "hashicorp/local"
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

provider "aws" {
  alias   = "read_only"
  profile = "ro_user"
  region  = "us-east-1"

  shared_config_files      = ["${path.root}/.aws/conf"]
  shared_credentials_files = ["${path.root}/.aws/credentials"]

  assume_role {
    role_arn = "arn:aws:iam::000000000000:role/ReadOnlyRoleChallenge35"
  }

  endpoints {
    iam = "http://localhost:4566"
    sts = "http://localhost:4566"
  }
}

module "compute" {
  source        = "./modules/compute"
  name          = "terraform-launch-template-35"
  image_id      = "ami-00000000000000000"
  instance_type = "t2.micro"
}


module "iam" {
  source               = "./modules/iam"
  iam_user_name        = "success-user-35"
  iam_user_policy_name = "ec2-describe-policy-35"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action   = ["ec2:Describe*"]
      Effect   = "Allow"
      Resource = "*"
    }]
  })
}

data "aws_caller_identity" "local" {
  provider = aws.read_only
}

resource "local_file" "this" {
  content  = data.aws_caller_identity.local.account_id
  filename = "account-number.txt"
}
