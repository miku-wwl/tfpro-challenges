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
  s3_use_path_style           = true

  endpoints {
    ec2 = "http://localhost:4566"
    iam = "http://localhost:4566"
    s3  = "http://localhost:4566"
    sts = "http://localhost:4566"
  }

  default_tags {
    tags = {
      Environment = var.environement
    }
  }
}

module "random" {
  source = "./modules/random"
}

module "ec2" {
  source               = "./modules/ec2"
  instance_type        = "t2.micro"
  iam_instance_profile = module.iam.instance_profile_name
}

data "aws_iam_policy_document" "assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}


module "iam" {
  source             = "./modules/iam"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
  random_pet         = module.random.random_pet
  org-name           = var.org-name
}

module "s3" {
  source         = "./modules/s3"
  s3_buckets     = toset(var.s3_buckets)
  s3_base_object = var.s3_base_object
  random_pet     = module.random.random_pet
}

module "sg" {
  source  = "./modules/sg"
  sg_name = var.sg_name

  cidr_ipv4   = "10.0.0.0/8"
  from_port   = 80
  ip_protocol = "tcp"
  to_port     = 80
}