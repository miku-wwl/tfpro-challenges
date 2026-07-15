data "terraform_remote_state" "foundation" {
  backend = "s3"
  config = {
    bucket                      = var.state_bucket
    key                         = var.foundation_state_key
    region                      = var.primary_region
    endpoint                    = var.localstack_endpoint
    access_key                  = "test"
    secret_key                  = "test"
    force_path_style            = true
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_requesting_account_id  = true
  }
}

data "aws_ami" "primary" {
  most_recent = true
  owners      = ["099720109477"]
}

# TODO: DR AMI 必须显式路由到 aws.dr。
data "aws_ami" "dr" {
  most_recent = true
  owners      = ["099720109477"]
}

locals {
  compute = try(data.terraform_remote_state.foundation.outputs.compute_contract, {})
  rows    = csvdecode(file(var.fleet_csv_path))

  # TODO: 行号不是稳定业务身份；应规范化、分组并独立验证输入。
  fleets = {
    for index, row in local.rows : tostring(index) => {
      name          = trimspace(try(row.name, ""))
      environment   = trimspace(try(row.environment, ""))
      location      = trimspace(try(row.location, ""))
      instance_type = trimspace(try(row.instance_type, ""))
      owner         = trimspace(try(row.owner, ""))
      enabled       = trimspace(try(row.enabled, "")) == "true"
      key           = tostring(index)
    } if trimspace(try(row.environment, "")) == var.target_environment && trimspace(try(row.enabled, "")) == "true"
  }
  primary_fleets  = local.fleets
  dr_fleets       = {}
  fleets_by_owner = {}
}

module "primary" {
  source           = "./modules/regional"
  providers        = { aws = aws }
  run_id           = var.run_id
  role             = "primary"
  ami_id           = data.aws_ami.primary.id
  fleets           = local.primary_fleets
  network          = try(local.compute.primary, {})
  instance_profile = try(local.compute.identity.instance_profile_name, "invalid")
}

module "dr" {
  source = "./modules/regional"
  # TODO: DR module 必须显式传递 aws.dr。
  providers        = { aws = aws }
  run_id           = var.run_id
  role             = "dr"
  ami_id           = data.aws_ami.dr.id
  fleets           = local.dr_fleets
  network          = try(local.compute.dr, {})
  instance_profile = try(local.compute.identity.instance_profile_name, "invalid")
}
