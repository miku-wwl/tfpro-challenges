provider "aws" {
  alias                       = "primary"
  region                      = var.primary_region
  access_key                  = "test"
  secret_key                  = "test"
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true
  s3_use_path_style           = true

  endpoints {
    s3  = var.localstack_endpoint
    sns = var.localstack_endpoint
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
  s3_use_path_style           = true

  endpoints {
    s3  = var.localstack_endpoint
    sns = var.localstack_endpoint
    sts = var.localstack_endpoint
  }
}

module "platform" {
  source = "./modules/platform"

  bucket_prefix = var.bucket_prefix

  providers = {
    aws.primary = aws.primary
    # TODO: 这里错误地把 DR 路由到 primary。
    aws.dr = aws.primary
  }
}

# TODO: 根据 fixtures/legacy-addresses.txt 声明四次 state-preserving move。
