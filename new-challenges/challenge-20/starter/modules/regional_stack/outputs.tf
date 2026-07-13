output "bucket_name" {
  value = module.storage.bucket_name
}

output "topic_arn" {
  value = aws_sns_topic.events.arn
}

output "contract" {
  value = {
    role        = var.role
    region      = var.expected_region
    bucket_name = module.storage.bucket_name
    topic_arn   = aws_sns_topic.events.arn
    peer_bucket = var.peer_bucket
  }
}

