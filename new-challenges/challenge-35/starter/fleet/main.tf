data "terraform_remote_state" "foundation" {
  backend = "local"
  config  = { path = "${path.module}/${var.foundation_state_path}" }
}
data "aws_ami" "primary" {
  most_recent = true
  owners      = ["amazon"]
}
# TODO: DR AMI 查询尚未路由给 aws.dr。
data "aws_ami" "dr" {
  most_recent = true
  owners      = ["amazon"]
}

locals {
  compute = data.terraform_remote_state.foundation.outputs.compute_contract
  rows    = csvdecode(file("${path.module}/${var.fleet_csv_path}"))
  # TODO: 行号不是稳定业务身份；应规范化、分组并拒绝重复/非法容量。
  fleets = {
    for index, row in local.rows : tostring(index) => {
      name             = trimspace(row.name), environment = trimspace(row.environment), location = trimspace(row.location),
      instance_type    = trimspace(row.instance_type), min_size = tonumber(row.min_size), max_size = tonumber(row.max_size),
      desired_capacity = tonumber(row.desired_capacity), owner = trimspace(row.owner), enabled = tobool(row.enabled), key = tostring(index)
    } if trimspace(row.environment) == var.target_environment && tobool(row.enabled)
  }
  primary_fleets  = { for key, fleet in local.fleets : key => fleet if fleet.location == "primary" }
  dr_fleets       = { for key, fleet in local.fleets : key => fleet if fleet.location == "dr" }
  fleets_by_owner = {}
}

resource "terraform_data" "contract_guard" {
  input = length(local.fleets)
  lifecycle {
    # TODO: 完成版本、区域、location、唯一性、名称和 capacity 合同。
    precondition {
      condition     = length(local.fleets) >= 0
      error_message = "Complete the fleet contract guard."
    }
  }
}

module "primary" {
  source    = "./modules/regional"
  providers = { aws = aws }

  run_id                = var.run_id
  role                  = "primary"
  ami_id                = data.aws_ami.primary.id
  fleets                = local.primary_fleets
  subnet_id             = local.compute.primary.subnet_id
  security_group_id     = local.compute.primary.security_group_id
  instance_profile_name = local.compute.identity.instance_profile_name
}
module "dr" {
  source = "./modules/regional"
  # TODO: DR module 当前错误地使用 default provider。
  providers = { aws = aws }

  run_id                = var.run_id
  role                  = "dr"
  ami_id                = data.aws_ami.dr.id
  fleets                = local.dr_fleets
  subnet_id             = local.compute.dr.subnet_id
  security_group_id     = local.compute.dr.security_group_id
  instance_profile_name = local.compute.identity.instance_profile_name
}
