provider "aws" {
  profile = "compute"
  region  = "us-east-1"

  shared_config_files      = ["${path.root}/.aws/conf"]
  shared_credentials_files = ["${path.root}/.aws/credentials"]

  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true

  endpoints {
    ec2 = "http://localhost:4566"
    iam = "http://localhost:4566"
    sts = "http://localhost:4566"
  }
}