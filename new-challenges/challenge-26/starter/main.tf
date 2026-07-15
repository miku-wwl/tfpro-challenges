locals {
  catalog_rows  = csvdecode(file(var.catalog_path))
  policy_source = jsondecode(file(var.policy_catalog_path))

  # TODO: normalize team/workload/policy and group by stable team-workload identity.
  access_catalog = {
    for index, row in local.catalog_rows : tostring(index) => row
  }
}

# TODO: validate duplicate identities, unknown policies, empty documents, wildcard actions,
# and non-ARN resources without adding IAM-domain features outside the exam contract.

# TODO: call modules/access-role with stable for_each keys.
