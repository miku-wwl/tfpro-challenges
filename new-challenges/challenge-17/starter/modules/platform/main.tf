module "primary" {
  source = "../regional-stack"

  role               = "primary"
  bucket_name        = "${var.bucket_prefix}-primary"
  peer_topic_arn     = null
  expected_peer_role = null

  providers = {
    aws.workload = aws.primary
  }
}

module "dr" {
  source = "../regional-stack"

  role        = "dr"
  bucket_name = "${var.bucket_prefix}-dr"

  # TODO: 通过 primary output 传递 peer topic，并显式声明平台顺序策略。
  peer_topic_arn     = null
  expected_peer_role = null

  providers = {
    # TODO: DR stack 使用了错误的 provider。
    aws.workload = aws.primary
  }
}

