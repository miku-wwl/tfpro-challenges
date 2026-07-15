data "terraform_remote_state" "artifact" {
  backend = "s3"
  config = {
    bucket                      = var.state_bucket
    key                         = var.artifact_state_key
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
data "aws_subnet" "primary" { id = var.primary_subnet_id }
# TODO: DR data sources 必须显式路由到 aws.dr。
data "aws_subnet" "dr" { id = var.dr_subnet_id }
data "aws_ami" "primary" {
  most_recent = true
  owners      = ["099720109477"]
}
data "aws_ami" "dr" {
  most_recent = true
  owners      = ["099720109477"]
}
data "aws_iam_policy_document" "ec2_trust" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

locals {
  release = try(data.terraform_remote_state.artifact.outputs.release_contract, {})
  catalog = jsondecode(file(abspath("${path.root}/${var.runtime_catalog_path}")))
  rows = [for row in try(local.catalog.fleets, []) : {
    name          = trimspace(try(row.name, ""))
    location      = trimspace(try(row.location, ""))
    artifact      = trimspace(try(row.artifact, ""))
    instance_type = trimspace(try(row.instance_type, ""))
    fields        = sort(keys(row))
  }]
  # TODO: 行号不是稳定 fleet identity；应以 name@location 分组并拒绝重复。
  fleets         = { for index, fleet in local.rows : tostring(index) => merge(fleet, { key = tostring(index) }) }
  primary_fleets = local.fleets
  dr_fleets      = {}
}

resource "aws_iam_role" "runtime" {
  name               = "${var.run_id}-runtime-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_trust.json
  tags               = { RunId = var.run_id, Lab = "challenge-40", ManagedBy = "terraform" }
}
resource "aws_iam_instance_profile" "runtime" {
  name = "${var.run_id}-runtime-profile"
  role = aws_iam_role.runtime.name
  tags = { RunId = var.run_id, Lab = "challenge-40", ManagedBy = "terraform" }
}

module "primary" {
  source           = "./modules/regional"
  providers        = { aws = aws }
  run_id           = var.run_id
  role             = "primary"
  region           = var.primary_region
  ami_id           = data.aws_ami.primary.id
  subnet_id        = data.aws_subnet.primary.id
  vpc_id           = data.aws_subnet.primary.vpc_id
  instance_profile = aws_iam_instance_profile.runtime.name
  fleets           = local.primary_fleets
  release_contract = local.release
}
module "dr" {
  source = "./modules/regional"
  # TODO: DR module 必须传递 aws.dr。
  providers        = { aws = aws }
  run_id           = var.run_id
  role             = "dr"
  region           = var.dr_region
  ami_id           = data.aws_ami.dr.id
  subnet_id        = data.aws_subnet.dr.id
  vpc_id           = data.aws_subnet.dr.vpc_id
  instance_profile = aws_iam_instance_profile.runtime.name
  fleets           = local.dr_fleets
  release_contract = local.release
}
