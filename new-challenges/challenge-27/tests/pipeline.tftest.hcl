mock_provider "aws" {
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }

  mock_resource "aws_s3_bucket" {
    defaults = {
      bucket = "tfpro-c27-dev-releases"
      arn    = "arn:aws:s3:::tfpro-c27-dev-releases"
    }
  }

  mock_resource "aws_s3_object" {
    defaults = {
      etag = "mock-etag"
    }
  }

  mock_resource "aws_sns_topic" {
    defaults = {
      arn = "arn:aws:sns:us-east-1:000000000000:tfpro-c27-dev-releases"
    }
  }
}

run "publishes_auditable_graph" {
  command = plan

  assert {
    condition     = length(output.managed_addresses) == 5
    error_message = "发布图必须包含 bucket、object、notification、topic、topic policy。"
  }

  assert {
    condition     = output.object_key == "releases/1.0.0/manifest.json"
    error_message = "object key 必须编码 release version。"
  }
}

run "identity_contains_manifest_digest" {
  command = plan

  assert {
    condition     = startswith(output.release_identity, "1.0.0:") && length(output.release_identity) == 70
    error_message = "release identity 必须包含版本和 SHA-256。"
  }
}

run "new_release_has_new_stable_key" {
  command = plan

  variables {
    release_version = "1.1.0-rc.1+build.7"
    manifest_path   = "../fixtures/release-prerelease.json"
  }

  assert {
    condition     = output.object_key == "releases/1.1.0-rc.1+build.7/manifest.json"
    error_message = "新版本必须映射到确定性的 release key。"
  }
}

run "rejects_invalid_semver" {
  command = plan

  variables {
    release_version = "01.0.0"
  }

  expect_failures = [var.release_version]
}

run "rejects_manifest_contract_mismatch" {
  command = plan

  variables {
    manifest_path = "../fixtures/release-invalid.json"
  }

  expect_failures = [check.manifest_contract, aws_s3_object.manifest]
}
