locals {
  directory_path = abspath("${path.root}/${var.directory_path}")
  raw_directory  = try(jsondecode(file(local.directory_path)), {})
  raw_entries    = try(tolist(local.raw_directory.entries), [])

  # TODO 1: validate and canonicalize the nested directory without losing duplicate evidence.
  entries_by_id = {}
}

data "aws_caller_identity" "current" {}
data "aws_iam_session_context" "current" { arn = data.aws_caller_identity.current.arn }

data "aws_iam_policy_document" "trust" {
  for_each = local.entries_by_id
  # TODO 2: compile sorted service principals into a canonical trust statement.
}

data "aws_iam_policy_document" "permissions" {
  for_each = local.entries_by_id
  # TODO 3: compile SID-keyed dynamic statements with sorted actions/resources.
}

resource "aws_iam_role" "directory" {
  for_each           = local.entries_by_id
  name               = "${var.run_id}-${each.key}-role"
  assume_role_policy = data.aws_iam_policy_document.trust[each.key].json
  # TODO 4: add the exact trace tags.
}

resource "aws_iam_policy" "directory" {
  for_each = local.entries_by_id
  name     = "${var.run_id}-${each.key}-policy"
  policy   = data.aws_iam_policy_document.permissions[each.key].json
  # TODO 5: add description and the exact trace tags.
}

resource "aws_iam_role_policy_attachment" "directory" {
  for_each   = local.entries_by_id
  role       = aws_iam_role.directory[each.key].name
  policy_arn = aws_iam_policy.directory[each.key].arn
}
