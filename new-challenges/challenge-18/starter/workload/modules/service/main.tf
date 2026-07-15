resource "aws_s3_object" "service" {
  bucket       = var.bucket_name
  key          = "services/${var.environment}/${var.service.name}.json"
  content      = jsonencode(var.service)
  content_type = "application/json"
  etag         = md5(jsonencode(var.service))
  metadata     = { owner = var.service.owner, tier = var.service.tier, location = var.location }
  tags         = { ManagedBy = "terraform", Service = var.service.name, Owner = var.service.owner, Location = var.location }

  lifecycle {
    precondition {
      condition     = var.platform_schema_version == 1
      error_message = "The workload requires platform contract schema version 1."
    }
  }
}
