# Legacy backend。TODO: 改成部分配置的 backend "s3" {} 后执行 init -migrate-state。
terraform {
  backend "local" {
    path = "legacy-producer.tfstate"
  }
}
