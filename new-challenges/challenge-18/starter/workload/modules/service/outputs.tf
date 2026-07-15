output "profile" {
  value = { service = var.service.name, owner = var.service.owner, location = var.location, key = aws_s3_object.service.key, id = aws_s3_object.service.id }
}
