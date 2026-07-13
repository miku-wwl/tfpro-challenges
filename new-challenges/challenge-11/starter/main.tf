module "replicated_storage" {
  source = "./modules/replicated-storage"

  # TODO: provider slots 被交换了。修复显式映射，不能依赖隐式继承。
  providers = {
    aws.primary  = aws.recovery
    aws.recovery = aws
  }

  name_prefix = var.name_prefix
  common_tags = var.common_tags
}

