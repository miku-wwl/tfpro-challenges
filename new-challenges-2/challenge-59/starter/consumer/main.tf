data "terraform_remote_state" "publisher" {
  backend = "s3"
  config = {
    bucket                      = var.state_bucket
    key                         = var.publisher_state_key
    region                      = var.aws_region
    access_key                  = "test"
    secret_key                  = "test"
    use_path_style              = true
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_requesting_account_id  = true
    endpoints = {
      s3 = var.localstack_endpoint
    }
  }
}

data "aws_ami" "selected" {
  most_recent = true
  owners      = ["self"]
  filter {
    name   = "name"
    values = [var.image_name]
  }
}

data "aws_subnet" "selected" {
  id = var.subnet_id
}

locals {
  contract     = try(data.terraform_remote_state.publisher.outputs.artifact_contract, {})
  raw_manifest = try(jsondecode(file("${path.module}/${var.manifest_path}")), {})
  node_rows = try([
    for node in local.raw_manifest.nodes : {
      name          = lower(trimspace(try(node.name, "")))
      artifact      = lower(trimspace(try(node.artifact, "")))
      instance_type = trimspace(try(node.instance_type, ""))
      fields        = sort(keys(node))
    }
  ], [])
  node_groups = { for node in local.node_rows : node.name => node... }

  contract_schema_valid    = false # TODO: enforce the exact remote output and nested artifact shapes.
  contract_integrity_valid = false # TODO: verify run/revision/bucket/ARN/owner/digest and canonical fingerprint.
  manifest_valid           = false # TODO: enforce manifest shape, identities, types, uniqueness, and artifact references.

  aggregate_valid = local.contract_schema_valid && local.contract_integrity_valid && local.manifest_valid
  nodes_by_name   = {} # TODO: derive stable node identities only after every contract succeeds.
  common_tags = {
    Challenge = "59"
    ManagedBy = "terraform"
    RunId     = var.run_id
    State     = "consumer"
  }
  release_payloads = {} # TODO: build one canonical JSON payload per node for both LT audit spec and EC2 runtime.
}

resource "aws_security_group" "runtime" {
  name        = "tfpro-c59-${var.run_id}"
  description = "Challenge 59 runtime traffic"
  vpc_id      = data.aws_subnet.selected.vpc_id

  ingress {
    description = "Application traffic"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = [data.aws_subnet.selected.cidr_block]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = local.common_tags

  lifecycle {
    precondition {
      condition     = local.contract_schema_valid
      error_message = "Remote artifact contract schema check failed."
    }
    precondition {
      condition     = !local.contract_schema_valid || local.contract_integrity_valid
      error_message = "Remote artifact contract integrity check failed."
    }
    precondition {
      condition     = local.manifest_valid
      error_message = "Deployment manifest schema or semantics check failed."
    }
  }
}

resource "aws_launch_template" "node" {
  for_each = local.nodes_by_name

  name          = "${var.run_id}-${each.key}"
  image_id      = data.aws_ami.selected.id
  instance_type = each.value.instance_type
  user_data     = null # TODO: encode the shared canonical release payload for the LT audit spec.

  tag_specifications {
    resource_type = "instance"
    tags = merge(local.common_tags, {
      Artifact = each.value.artifact
      Node     = each.key
      Revision = local.contract.revision
    })
  }
}

resource "aws_instance" "node" {
  for_each = local.nodes_by_name

  ami                         = data.aws_ami.selected.id
  instance_type               = each.value.instance_type
  subnet_id                   = data.aws_subnet.selected.id
  vpc_security_group_ids      = [aws_security_group.runtime.id]
  user_data                   = null  # TODO: mirror the exact canonical payload into the real EC2 runtime.
  user_data_replace_on_change = false # TODO: make payload changes replace the runtime.
  tags = merge(local.common_tags, {
    Name           = "${var.run_id}-${each.key}"
    Artifact       = each.value.artifact
    ArtifactDigest = local.contract.artifacts[each.value.artifact].content_sha256
    Node           = each.key
    Revision       = local.contract.revision
  })

  lifecycle {
    create_before_destroy = false # TODO: preserve availability during release replacement.
    replace_triggered_by  = []    # TODO: link replacement to the matching LT audit-spec revision.
  }
}
