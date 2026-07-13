output "contract" {
  value = {
    bucket = aws_s3_bucket.artifact.id
    topic  = aws_sns_topic.events.arn
    region = var.network.region
    owner  = var.application.owner
    port   = var.application.port
  }
}

