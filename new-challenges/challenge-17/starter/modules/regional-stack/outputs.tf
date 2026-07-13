output "inventory" {
  value = {
    role           = var.role
    region         = data.aws_region.current.name
    bucket_id      = aws_s3_bucket.logs.id
    topic_arn      = aws_sns_topic.events.arn
    peer_topic_arn = var.peer_topic_arn
  }
}

