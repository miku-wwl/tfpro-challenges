data "terraform_remote_state" "artifact" {
  backend = "local"
  config = {
    path = abspath("${path.root}/${var.artifact_state_path}")
  }
}

data "aws_ami" "primary" {
  most_recent = true
  owners      = ["amazon"]
}

# TODO 5: DR AMI 查询必须显式路由到 aws.dr。
data "aws_ami" "dr" {
  most_recent = true
  owners      = ["amazon"]
}

data "aws_vpc" "primary" {
  default = true
}

data "aws_vpc" "dr" {
  provider = aws.dr
  default  = true
}

data "aws_subnets" "primary" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.primary.id]
  }
}

data "aws_subnets" "dr" {
  provider = aws.dr
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.dr.id]
  }
}

locals {
  release_contract = data.terraform_remote_state.artifact.outputs.release_contract
  catalog          = jsondecode(file(abspath("${path.root}/${var.runtime_catalog_path}")))
  catalog_rows = [
    for row in try(local.catalog.fleets, []) : {
      name          = trimspace(try(row.name, ""))
      location      = trimspace(try(row.location, ""))
      artifact      = trimspace(try(row.artifact, ""))
      instance_type = trimspace(try(row.instance_type, ""))
      replicas      = try(tonumber(row.replicas), 0)
    }
  ]

  # TODO 6: 用 name@location 分组后拒绝重复，不能使用 JSON 行号作为资源身份。
  fleets = {
    for index, fleet in local.catalog_rows : tostring(index) => merge(fleet, { key = tostring(index) })
  }
  primary_fleets = {
    for key, fleet in local.fleets : key => fleet if fleet.location == "primary"
  }
  dr_fleets = {
    for key, fleet in local.fleets : key => fleet if fleet.location == "dr"
  }
}

resource "terraform_data" "contract_guard" {
  input = length(local.fleets)

  lifecycle {
    # TODO 7: 完成 11 个独立且单一职责的 guards：release contract 版本/区域/版本号、本 run bucket、
    # 安全 object keys、严格 sha256，以及 catalog schema/数量/唯一性/字段/artifact 引用；不得合并或填空壳。
    precondition {
      condition     = length(local.fleets) >= 0
      error_message = "Complete the release and runtime contract guards."
    }
  }
}

resource "aws_iam_role" "runtime" {
  name = "${var.run_id}-runtime-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = {
    RunId     = var.run_id
    Lab       = "challenge-40"
    ManagedBy = "terraform"
  }
}

resource "aws_iam_instance_profile" "runtime" {
  name = "${var.run_id}-runtime-profile"
  role = aws_iam_role.runtime.name

  tags = {
    RunId     = var.run_id
    Lab       = "challenge-40"
    ManagedBy = "terraform"
  }
}

module "primary" {
  source    = "./modules/regional"
  providers = { aws = aws }

  run_id                = var.run_id
  role                  = "primary"
  region                = var.primary_region
  ami_id                = data.aws_ami.primary.id
  vpc_id                = data.aws_vpc.primary.id
  subnet_id             = sort(data.aws_subnets.primary.ids)[0]
  instance_profile_name = aws_iam_instance_profile.runtime.name
  fleets                = local.primary_fleets
  release_contract      = local.release_contract

  depends_on = [terraform_data.contract_guard]
}

module "dr" {
  source = "./modules/regional"
  # TODO 8: DR module 必须显式传递 aws.dr。
  providers = { aws = aws }

  run_id                = var.run_id
  role                  = "dr"
  region                = var.dr_region
  ami_id                = data.aws_ami.dr.id
  vpc_id                = data.aws_vpc.dr.id
  subnet_id             = sort(data.aws_subnets.dr.ids)[0]
  instance_profile_name = aws_iam_instance_profile.runtime.name
  fleets                = local.dr_fleets
  release_contract      = local.release_contract

  depends_on = [terraform_data.contract_guard]
}
