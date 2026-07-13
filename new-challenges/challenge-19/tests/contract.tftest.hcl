mock_provider "aws" {}

# Static import blocks are part of the Terraform 1.6-compatible production
# configuration. Terraform test cannot import through a mock provider, so the
# two pre-existing objects are explicitly overridden for this canonical plan.
override_resource {
  target = aws_s3_bucket.archive
  values = {
    id     = "tfpro-c19-mock-archive"
    bucket = "tfpro-c19-mock-archive"
  }
}

override_resource {
  target = aws_dynamodb_table.locks
  values = {
    id   = "tfpro-c19-mock-locks"
    name = "tfpro-c19-mock-locks"
  }
}

run "canonical_contract_without_adoption" {
  command = plan

  variables {
    name_prefix = "tfpro-c19-mock"
  }

  assert {
    condition     = output.adoption_contract.bucket_name == "tfpro-c19-mock-archive"
    error_message = "bucket name must be stable and derived from name_prefix"
  }

  assert {
    condition     = output.adoption_contract.table_name == "tfpro-c19-mock-locks"
    error_message = "table name must be stable and derived from name_prefix"
  }

  assert {
    condition     = output.adoption_contract.manifest == "releases/manifest.json"
    error_message = "release manifest key is part of the migration contract"
  }

  assert {
    condition     = output.canonical_addresses == ["aws_s3_bucket.archive", "aws_dynamodb_table.locks", "aws_s3_object.release_manifest", "terraform_data.inventory"]
    error_message = "only canonical post-migration addresses may be exposed"
  }
}
