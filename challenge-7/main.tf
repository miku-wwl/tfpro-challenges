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


output "list_list_condition" {
  value = [for ec2 in local.ec2_csv : [ec2.Region] if ec2.instance_type == "nano"]
}




output "instance_count_by_type" {
  value = {
    micro = length([
      for row in local.ec2_csv : row
      if row.instance_type == "micro"
    ])
    nano = length([
      for row in local.ec2_csv : row
      if row.instance_type == "nano"
    ])
  }
}

output "instance_details" {
  value = [for ec2 in local.ec2_csv : { team = ec2.Team_Name, type = ec2.instance_type }]
}


output "map_of_maps" {
  value = { for ec2 in local.ec2_csv : "${ec2.instance_type}_${ec2.Region}_${ec2.Team_Name}" => {
    "ami_id"        = ec2.AMI_ID
    "instance_type" = ec2.instance_type
    "region"        = ec2.Region
    "team_name"     = ec2.Team_Name
  } }
}


