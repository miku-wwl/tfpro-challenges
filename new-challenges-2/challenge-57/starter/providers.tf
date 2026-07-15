provider "aws" {
  alias                       = "primary"
  region                      = var.primary_region
  access_key                  = "test"
  secret_key                  = "test"
  s3_use_path_style           = true
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true

  endpoints {
    s3  = var.localstack_endpoint
    sts = var.localstack_endpoint
  }
}

provider "aws" {
  alias = "replica"
  # TODO 2: route this slot independently to the replica region.
  region                      = var.primary_region
  access_key                  = "test"
  secret_key                  = "test"
  s3_use_path_style           = true
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true

  endpoints {
    s3  = var.localstack_endpoint
    sts = var.localstack_endpoint
  }
}
