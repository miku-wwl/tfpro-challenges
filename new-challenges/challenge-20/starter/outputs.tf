output "regional_contract" {
  value = {
    primary = module.primary.contract
    dr      = module.dr.contract
  }
}

output "failover_contract" {
  value = {
    source_bucket = module.primary.bucket_name
    target_bucket = module.dr.bucket_name
    primary_topic = module.primary.topic_arn
    dr_topic      = module.dr.topic_arn
  }
}

