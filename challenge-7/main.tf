terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
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

locals {
  ec2_csv = csvdecode(file("${path.module}/ec2.csv"))
}

output "list_amis" {
  value = [for ec2 in local.ec2_csv : ec2.AMI_ID]
}

output "unique_team_names" {
  value = distinct([for ec2 in local.ec2_csv : ec2.Team_Name])
}


output "regions_list_of_lists" {
  value = [for ec2 in local.ec2_csv : [ec2.Region]]
}  