output "contracts" {
  value = {
    for key, deployment in var.deployments : key => {
      region         = var.network_contract.region
      bucket         = aws_s3_bucket.artifact[key].id
      manifest_key   = aws_s3_object.manifest[key].key
      subnet_id      = var.network_contract.subnet_id
      security_group = var.platform_contract.sg_id
      topic_arn      = var.platform_contract.topic_arn
      table_name     = var.platform_contract.table_name
      port           = deployment.port
    }
  }
}
