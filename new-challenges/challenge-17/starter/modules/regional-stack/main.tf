data "aws_region" "current" {
  provider = aws.workload
}

resource "aws_sns_topic" "events" {
  provider = aws.workload
  name     = "${var.bucket_name}-events"

  tags = {
    Role = var.role
  }
}

resource "aws_s3_bucket" "logs" {
  provider = aws.workload
  bucket   = var.bucket_name

  tags = merge(
    { Role = var.role },
    var.peer_topic_arn == null ? {} : { PeerTopicArn = var.peer_topic_arn },
  )
}

resource "aws_s3_bucket_versioning" "logs" {
  provider = aws.workload
  bucket   = aws_s3_bucket.logs.id

  versioning_configuration {
    status = "Enabled"
  }
}

