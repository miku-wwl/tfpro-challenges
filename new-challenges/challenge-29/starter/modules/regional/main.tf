data "aws_region" "current" { provider = aws.workload }

resource "aws_s3_bucket" "artifact" {
  provider      = aws.workload
  for_each      = var.services
  bucket        = "${var.run_id}-${each.key}-${var.role}"
  force_destroy = true
  tags          = { Service = each.key, Owner = each.value.owner, Role = var.role }
}

resource "aws_dynamodb_table" "catalog" {
  provider     = aws.workload
  for_each     = var.services
  name         = "${var.run_id}-${each.key}-${var.role}"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"
  attribute {
    name = "id"
    type = "S"
  }
  tags = { Service = each.key, RetentionDays = tostring(each.value.retention_days) }
}

resource "aws_sns_topic" "events" {
  provider = aws.workload
  for_each = var.services
  name     = "${var.run_id}-${each.key}-${var.role}-events"
  tags = merge(
    { Service = each.key, Role = var.role },
    contains(keys(var.peer_topics), each.key) ? { PeerTopic = var.peer_topics[each.key] } : {},
  )
}
