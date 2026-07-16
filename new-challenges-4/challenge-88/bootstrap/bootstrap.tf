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
    sts = "http://localhost:4566"
  }
}

# This isolated root simulates an instance created by an earlier owner.
resource "aws_instance" "legacy" {
  ami           = "ami-04681a1dbd79675a5"
  instance_type = "t2.micro"

  tags = {
    Name      = "tfpro-challenge88-imported"
    Challenge = "88"
    Owner     = "legacy-platform"
  }
}

output "legacy_instance_id" {
  value = aws_instance.legacy.id
}
