output "contracts" {
  value = { for key in sort(keys(var.services)) : key => {
    region     = data.aws_region.current.name
    bucket     = aws_s3_bucket.artifact[key].id
    table      = aws_dynamodb_table.catalog[key].name
    topic      = aws_sns_topic.events[key].arn
    peer_topic = lookup(var.peer_topics, key, null)
  } }
}

