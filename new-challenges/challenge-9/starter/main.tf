locals {
  manifest_content = jsonencode({ services = var.catalog })
  indexed_catalog  = { for index, name in sort(keys(var.catalog)) : tostring(index) => merge(var.catalog[name], { name = name }) }

  services_by_owner = {
    # TODO: 按 owner 聚合并稳定排序。目前这个占位结果会让测试失败。
    unknown = sort(keys(var.catalog))
  }
}

resource "terraform_data" "service" {
  # TODO: 数字 key 会让 CSV/集合重排改变资源身份，改为稳定服务名。
  for_each = local.indexed_catalog
  input    = each.value
}

resource "terraform_data" "guardian" {
  input = {
    name   = "ops-guardian"
    policy = "retain"
  }

  # TODO: 添加销毁保护，并通过 import block 接管既有 ID。
}

resource "local_file" "manifest" {
  filename        = var.manifest_path
  content         = local.manifest_content
  file_permission = "0644"

  # TODO: 添加安全替换 lifecycle。
}

# TODO: 为三个 workload 地址和 local_file.inventory 编写 moved blocks。
# TODO: 为 guardian 编写 Terraform 1.6 import block。

