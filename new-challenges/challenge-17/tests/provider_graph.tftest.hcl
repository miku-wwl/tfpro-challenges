mock_provider "aws" {
  alias = "primary"

  mock_data "aws_region" {
    defaults = {
      name = "us-east-1"
    }
  }

  mock_resource "aws_s3_bucket" {
    defaults = {
      id = "tfpro-c17-primary"
    }
  }

  mock_resource "aws_sns_topic" {
    defaults = {
      arn = "arn:aws:sns:us-east-1:111122223333:tfpro-c17-primary-events"
    }
  }
}

mock_provider "aws" {
  alias = "dr"

  mock_data "aws_region" {
    defaults = {
      name = "us-west-2"
    }
  }

  mock_resource "aws_s3_bucket" {
    defaults = {
      id = "tfpro-c17-dr"
    }
  }

  mock_resource "aws_sns_topic" {
    defaults = {
      arn = "arn:aws:sns:us-west-2:111122223333:tfpro-c17-dr-events"
    }
  }
}

run "aliases_reach_correct_nested_modules" {
  # apply is safe under mock_provider and resolves data sources deferred by
  # the explicit module-level depends_on edge.
  command = apply

  assert {
    condition     = output.regional_inventory.primary.region == "us-east-1"
    error_message = "Primary nested stack must use aws.primary."
  }

  assert {
    condition     = output.regional_inventory.dr.region == "us-west-2"
    error_message = "DR nested stack must use aws.dr, not aws.primary."
  }

  assert {
    condition     = output.regional_inventory.primary.role == "primary" && output.regional_inventory.dr.role == "dr"
    error_message = "Root and platform outputs must not cross-reference regional modules."
  }

  assert {
    condition     = output.failover_dependency.primary_topic == output.failover_dependency.dr_peer_topic
    error_message = "DR must consume primary topic ARN through a module output."
  }

  assert {
    condition     = output.failover_dependency.peer_role == "primary"
    error_message = "The peer role proves the cross-module contract is complete."
  }
}

run "reject_same_region" {
  command = plan

  variables {
    primary_region = "us-east-1"
    dr_region      = "us-east-1"
  }

  expect_failures = [var.dr_region]
}

run "reject_invalid_bucket_prefix" {
  command = plan

  variables {
    bucket_prefix = "Bad_Prefix"
  }

  expect_failures = [var.bucket_prefix]
}
