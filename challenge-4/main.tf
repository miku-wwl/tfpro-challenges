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
}

locals {
  ec2_instances     = csvdecode(file("${path.module}/ec2.csv"))
  ec2_instances_ue  = [for instance in local.ec2_instances : instance if instance.Region == "us-east-1"]
  instance_type_map = { micro = "t2.micro", nano = "t3.nano" }
  map_instance_type = { "t2.micro" = "micro", "t3.nano" = "nano" }
}

resource "aws_instance" "ec2" {
  count = length(local.ec2_instances_ue)

  instance_type = local.instance_type_map[local.ec2_instances_ue[count.index].instance_type]
  ami           = local.ec2_instances_ue[count.index].AMI_ID

  tags = {
    Name = local.ec2_instances_ue[count.index].Team_Name
  }
}

output "running_ec2" {
  value = [
    for value in aws_instance.ec2 : {
      firewall_id = value.vpc_security_group_ids
      id          = value.id
      region      = "us-east-1"
      subnet      = value.subnet_id
      team        = value.tags.Name
      type        = local.map_instance_type[value.instance_type]
    }
  ]
}