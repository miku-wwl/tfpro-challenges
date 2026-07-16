# resource "terraform_data" "service" {
#   count = length(var.services)

#   input = {
#     name        = var.services[count.index].name
#     port        = var.services[count.index].port
#     owner       = var.services[count.index].owner
#     tier        = var.services[count.index].tier
#     environment = var.environment
#     tags        = var.common_tags
#   }
# }



module "service" {
  for_each = {
    for service in var.services : service.name => service
  }

  source = "./modules/service"

  service = each.value
  context = {
    environment = var.environment
    tags        = var.common_tags
  }
}

moved {
  from = module.service["api"].terraform_data.service
  to   = module.service["api"].terraform_data.this
}

moved {
  from = module.service["web"].terraform_data.service
  to   = module.service["web"].terraform_data.this
}

moved {
  from = module.service["worker"].terraform_data.service
  to   = module.service["worker"].terraform_data.this
}
