module "service" {
  # TODO: 这是中间态的 count module，目标必须是稳定服务名 for_each。
  count  = length(var.services)
  source = "./modules/service"

  name        = var.services[count.index].name
  port        = var.services[count.index].port
  owner       = var.services[count.index].owner
  tier        = var.services[count.index].tier
  healthcheck = var.services[count.index].healthcheck
  environment = var.environment
  tags        = var.common_tags
}
