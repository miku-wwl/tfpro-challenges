data "terraform_remote_state" "producer" {
  backend = "s3"

  # TODO: 补全 LocalStack S3 backend 的安全配置、test/test、skip flags 和 path-style。
  config = {
    bucket = var.state_bucket
    key    = var.producer_state_key
    region = var.aws_region
  }
}

resource "terraform_data" "snapshot" {
  input = data.terraform_remote_state.producer.outputs.platform_contract
}
