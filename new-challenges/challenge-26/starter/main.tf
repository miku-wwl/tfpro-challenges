locals {
  catalog_rows  = csvdecode(file(var.catalog_path))
  policy_source = jsondecode(file(var.policy_catalog_path))

  # TODO: 行号会随 CSV 重排而改变。改成规范化的 team-workload key，
  # 并合并策略目录中的 actions/resources。
  access_catalog = {
    for index, row in local.catalog_rows : tostring(index) => row
  }
}

# TODO: 添加重复 identity、未知 policy、空权限及 Action="*" checks。
# TODO: 创建统一 permissions-boundary policy。
# TODO: 使用 for_each 调用 modules/access-role。

