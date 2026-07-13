locals {
  decoded_fleets = [
    for row in csvdecode(file(var.fleet_csv_path)) : {
      fleet_id         = trimspace(row.fleet_id)
      environment      = lower(trimspace(row.environment))
      subnet_key       = trimspace(row.subnet_key)
      instance_type    = trimspace(row.instance_type)
      min_size         = try(tonumber(trimspace(row.min_size)), -1)
      desired_capacity = try(tonumber(trimspace(row.desired_capacity)), -1)
      max_size         = try(tonumber(trimspace(row.max_size)), -1)
      enabled_text     = lower(trimspace(row.enabled))
      enabled          = lower(trimspace(row.enabled)) == "true"
      owner            = trimspace(row.owner)
    }
  ]

  # TODO: 只有目标环境且 enabled=true 的行可以进入 graph。
  active_fleets = [
    for fleet in local.decoded_fleets : fleet
    if fleet.environment == var.environment
  ]

  fleet_groups = {
    for fleet in local.active_fleets : fleet.fleet_id => fleet...
  }

  fleets_by_id = {
    for fleet_id, group in local.fleet_groups : fleet_id => group[0]
  }

  # TODO: 使用 fleet_id/ordinal，而不是 CSV 行号，形成稳定的实例 key。
  instances_by_key = {
    for instance in flatten([
      for fleet_id, fleet in local.fleets_by_id : [
        for ordinal in range(max(0, floor(fleet.desired_capacity))) : {
          key        = "${fleet_id}/${format("%02d", ordinal + 1)}"
          fleet_id   = fleet_id
          ordinal    = ordinal + 1
          subnet_key = fleet.subnet_key
          owner      = fleet.owner
        }
      ]
    ]) : instance.key => instance
  }
}

# TODO: 添加 fleet ID 唯一、整数容量范围、subnet 引用以及字段/布尔值 checks。

data "aws_ami" "selected" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-*-amd64-server-*"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}

resource "aws_vpc" "this" {
  cidr_block           = var.network.cidr_block
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name      = "${var.name_prefix}-vpc"
    ManagedBy = "terraform"
    RunId     = var.run_id
  }
}

resource "aws_subnet" "this" {
  for_each = var.network.subnets

  vpc_id            = aws_vpc.this.id
  cidr_block        = each.value.cidr_block
  availability_zone = each.value.availability_zone

  tags = {
    Name      = "${var.name_prefix}-${each.key}"
    Owner     = each.value.owner
    ManagedBy = "terraform"
    RunId     = var.run_id
  }
}

data "aws_vpc" "managed" {
  id = aws_vpc.this.id
}

data "aws_subnet" "managed" {
  for_each = aws_subnet.this
  id       = each.value.id
}

resource "aws_security_group" "fleet" {
  for_each = local.fleets_by_id

  name        = "${var.name_prefix}-${each.key}"
  description = "Compute fleet ${each.key}"
  vpc_id      = data.aws_vpc.managed.id

  tags = {
    Name      = "${var.name_prefix}-${each.key}"
    Owner     = each.value.owner
    FleetId   = each.key
    ManagedBy = "terraform"
    RunId     = var.run_id
  }
}

resource "aws_launch_template" "fleet" {
  for_each = local.fleets_by_id

  name                   = "${var.name_prefix}-${each.key}"
  image_id               = data.aws_ami.selected.id
  instance_type          = each.value.instance_type
  vpc_security_group_ids = [aws_security_group.fleet[each.key].id]

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name      = "${var.name_prefix}-${each.key}"
      Owner     = each.value.owner
      FleetId   = each.key
      ManagedBy = "terraform"
      RunId     = var.run_id
    }
  }

  tags = {
    Name      = "${var.name_prefix}-${each.key}"
    Owner     = each.value.owner
    FleetId   = each.key
    ManagedBy = "terraform"
    RunId     = var.run_id
  }

  lifecycle {
    create_before_destroy = true
    # TODO: 处理 LocalStack 对 launch-template tag specification 的回读差异。
  }
}

resource "aws_instance" "fleet" {
  for_each = local.instances_by_key

  subnet_id = data.aws_subnet.managed[each.value.subnet_key].id

  launch_template {
    id      = aws_launch_template.fleet[each.value.fleet_id].id
    version = "$Latest"
  }

  tags = {
    Name      = "${var.name_prefix}-${replace(each.key, "/", "-")}"
    Owner     = each.value.owner
    FleetId   = each.value.fleet_id
    Ordinal   = tostring(each.value.ordinal)
    ManagedBy = "terraform"
    RunId     = var.run_id
  }

  # TODO: 窄范围忽略 LocalStack 不回读的 launch_template 来源，并用 terraform_data revision sentinel 保留模板变更触发替换。
}
