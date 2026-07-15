terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
      version = "5.82.2"
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
  s3_use_path_style           = true

  endpoints {
    ec2 = "http://localhost:4566"
    iam = "http://localhost:4566"
    s3  = "http://localhost:4566"
    sts = "http://localhost:4566"
  }
}

resource "aws_vpc" "central_vpc" {
  cidr_block           = "10.0.0.0/16"
  tags = {
    Name = "central-vpc"
  }
}

resource "aws_subnet" "subnets" {
  for_each = {
    app         = "10.0.1.0/24"
    database    = "10.0.2.0/24"
    central     = "10.0.3.0/24"
  }

  vpc_id     = aws_vpc.central_vpc.id
  cidr_block = each.value

  tags = {
    Name = "${each.key}-subnet"
  }
}