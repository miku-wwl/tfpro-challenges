output "platform_contract" {
  value = {
    contract_version = 1
    primary = {
      region     = var.primary_region
      sg_id      = aws_security_group.primary.id
      topic_arn  = aws_sns_topic.primary.arn
      table_name = aws_dynamodb_table.primary.name
    }
    dr = {
      # TODO: Publish the actual DR resources instead of crossing back to primary.
      region     = var.primary_region
      sg_id      = aws_security_group.primary.id
      topic_arn  = aws_sns_topic.primary.arn
      table_name = aws_dynamodb_table.primary.name
    }
  }
}
