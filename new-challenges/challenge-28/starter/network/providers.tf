provider "aws" {
  region                      = var.primary_region
  access_key                  = "test"
  secret_key                  = "test"
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true
  endpoints {
    ec2 = var.localstack_endpoint
    sts = var.localstack_endpoint
  }
}

provider "aws" {
  alias                       = "dr"
  region                      = var.dr_region
  access_key                  = "test"
  secret_key                  = "test"
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true
  endpoints {
    ec2 = var.localstack_endpoint
    sts = var.localstack_endpoint
  }
}

