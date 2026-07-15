data "terraform_remote_state" "vpc" {
  backend = "s3"

  config = {
    bucket                      = "challenge-5-tfstate"
    key                         = "vpc.tfstate"
    region                      = "us-east-1"
    access_key                  = "test"
    secret_key                  = "test"
    endpoints                   = { s3 = "http://localhost:4566" }
    skip_credentials_validation = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    skip_metadata_api_check     = true
    use_path_style              = true
  }
}

module "ec2" {
  source = "../../modules/ec2"

  subnet_ids    = data.terraform_remote_state.vpc.outputs.subnet_ids
  ami           = "ami-00000000000000000"
  instance_type = "t2.micro"
}

module "sg" {
  source = "../../modules/sg"

  vpc_id = "vpc-f4df6ab13792845ec"
}
