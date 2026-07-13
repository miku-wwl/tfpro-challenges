mock_provider "aws" {
  mock_data "aws_ami" {
    defaults = {
      id           = "ami-0123456789abcdef0"
      architecture = "x86_64"
      state        = "available"
    }
  }

  mock_data "aws_vpc" {
    defaults = {
      cidr_block = "10.61.0.0/16"
    }
  }

  mock_data "aws_subnet" {
    defaults = {
      cidr_block = "10.61.99.0/24"
    }
  }
}

run "canonical_fleet_contract" {
  command = plan

  variables {
    name_prefix    = "tfpro-c31-mock"
    fleet_csv_path = "../fixtures/fleets.csv"
  }

  assert {
    condition     = output.active_fleet_ids == tolist(["api", "worker"])
    error_message = "仅 enabled prod fleets 可以进入 graph。"
  }

  assert {
    condition     = output.fleet_contract.capacities.api.desired_capacity == 2 && output.fleet_contract.capacities.worker.max_size == 4
    error_message = "容量必须经过数字标准化。"
  }

  assert {
    condition     = output.resource_addresses.instances == tolist(["aws_instance.fleet[\"api/01\"]", "aws_instance.fleet[\"api/02\"]", "aws_instance.fleet[\"worker/01\"]"])
    error_message = "实例地址必须使用稳定的 fleet_id/ordinal。"
  }
}

run "reordered_csv_is_stable" {
  command = plan

  variables {
    name_prefix    = "tfpro-c31-mock"
    fleet_csv_path = "../fixtures/fleets-reordered.csv"
  }

  assert {
    condition     = output.active_fleet_ids == tolist(["api", "worker"])
    error_message = "CSV 重排不能改变 fleet IDs。"
  }

  assert {
    condition     = output.resource_addresses.launch_templates == tolist(["aws_launch_template.fleet[\"api\"]", "aws_launch_template.fleet[\"worker\"]"])
    error_message = "CSV 重排不能改变 launch template 地址。"
  }
}

run "invalid_environment" {
  command = plan

  variables {
    environment = "qa"
  }

  expect_failures = [var.environment]
}

run "duplicate_active_fleet_id" {
  command = plan

  variables {
    fleet_csv_path = "../fixtures/fleets-duplicate.csv"
  }

  expect_failures = [check.fleet_ids_unique]
}

run "invalid_capacity_bounds" {
  command = plan

  variables {
    fleet_csv_path = "../fixtures/fleets-invalid-capacity.csv"
  }

  expect_failures = [check.fleet_capacity_bounds]
}

run "unknown_subnet" {
  command = plan

  variables {
    fleet_csv_path = "../fixtures/fleets-invalid-subnet.csv"
  }

  expect_failures = [check.fleet_subnets_exist]
}

run "missing_csv_file" {
  command = plan

  variables {
    fleet_csv_path = "../fixtures/does-not-exist.csv"
  }

  expect_failures = [var.fleet_csv_path]
}

run "non_loopback_candidate_endpoint" {
  command = plan

  variables {
    localstack_endpoint = "https://aws.amazon.com"
  }

  expect_failures = [var.localstack_endpoint]
}

run "invalid_enabled_boolean" {
  command = plan

  variables {
    fleet_csv_path = "../fixtures/fleets-invalid-boolean.csv"
  }

  expect_failures = [check.fleet_fields_valid]
}

run "empty_required_fleet_fields" {
  command = plan

  variables {
    fleet_csv_path = "../fixtures/fleets-bad-fields.csv"
  }

  expect_failures = [check.fleet_fields_valid]
}

run "invalid_network_contract" {
  command = plan

  variables {
    network = {
      cidr_block = "not-a-cidr"
      subnets = {
        broken-a = {
          cidr_block        = "10.61.10.0/24"
          availability_zone = "us-east-1a"
          owner             = "edge"
        }
      }
    }
  }

  expect_failures = [var.network]
}
