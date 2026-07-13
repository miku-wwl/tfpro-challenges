mock_provider "aws" {
  alias = "primary"

  mock_data "aws_region" {
    defaults = { name = "us-east-1" }
  }
  mock_resource "aws_s3_bucket" {
    defaults = { id = "primary-bucket" }
  }
  mock_resource "aws_dynamodb_table" {
    defaults = { name = "primary-table" }
  }
  mock_resource "aws_sns_topic" {
    defaults = { arn = "arn:aws:sns:us-east-1:000000000000:primary-events" }
  }
}

mock_provider "aws" {
  alias = "dr"

  mock_data "aws_region" {
    defaults = { name = "us-west-2" }
  }
  mock_resource "aws_s3_bucket" {
    defaults = { id = "dr-bucket" }
  }
  mock_resource "aws_dynamodb_table" {
    defaults = { name = "dr-table" }
  }
  mock_resource "aws_sns_topic" {
    defaults = { arn = "arn:aws:sns:us-west-2:000000000000:dr-events" }
  }
}

run "stable_filtered_catalog" {
  command = plan

  assert {
    condition     = join(",", output.service_keys) == "api,metrics,worker"
    error_message = "Only enabled prod services may be selected, keyed by service name."
  }
  assert {
    condition     = join(",", sort(keys(output.regional_contracts))) == "dr,primary"
    error_message = "The replication contract must expose primary and dr."
  }
  assert {
    condition     = output.regional_contracts.primary.api.table == "tfpro-c29-api-primary" && output.regional_contracts.dr.api.table == "tfpro-c29-api-dr"
    error_message = "Primary and DR regional resource contracts are crossed."
  }
  assert {
    condition     = output.regional_contracts.dr.api.peer_topic == output.regional_contracts.primary.api.topic
    error_message = "DR must consume the matching primary SNS topic contract."
  }
  assert {
    condition     = join(",", output.services_by_owner.platform) == "api" && join(",", output.services_by_owner.data) == "worker"
    error_message = "Owner grouping is incomplete or unstable."
  }
}

run "reordered_catalog_is_stable" {
  command = plan
  variables {
    catalog_file = "../fixtures/services-reordered.csv"
  }

  assert {
    condition     = join(",", output.service_keys) == "api,metrics,worker"
    error_message = "CSV row order must not change service identity."
  }
  assert {
    condition     = output.regional_contracts.dr.metrics.peer_topic == output.regional_contracts.primary.metrics.topic
    error_message = "The DR-to-primary topic contract must remain keyed by service name."
  }
}

run "reject_unknown_environment" {
  command = plan
  variables {
    target_environment = "qa"
  }
  expect_failures = [var.target_environment]
}

run "reject_same_region" {
  command = plan
  variables {
    dr_region = "us-east-1"
  }
  expect_failures = [var.dr_region]
}

run "reject_bad_run_id" {
  command = plan
  variables {
    run_id = "BAD"
  }
  expect_failures = [var.run_id]
}
