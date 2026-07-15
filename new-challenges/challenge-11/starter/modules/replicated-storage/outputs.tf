output "provider_regions" {
  value = {
    primary  = var.primary_region
    recovery = var.recovery_region
  }
}

output "caller_accounts" {
  value = {
    primary  = data.aws_caller_identity.primary.account_id
    recovery = data.aws_caller_identity.recovery.account_id
  }
}

output "caller_arns" {
  value = {
    primary  = data.aws_caller_identity.primary.arn
    recovery = data.aws_caller_identity.recovery.arn
  }
}

output "bucket_names" {
  value = {
    primary  = aws_s3_bucket.primary.bucket
    recovery = aws_s3_bucket.recovery.bucket
  }
}

