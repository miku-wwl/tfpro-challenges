locals {
  service_names = sort(keys(var.catalog))
  manifest_content = jsonencode({
    services = var.catalog
  })
}

resource "terraform_data" "workload" {
  count = length(local.service_names)

  input = merge(var.catalog[local.service_names[count.index]], {
    name = local.service_names[count.index]
  })
}

resource "terraform_data" "retired" {
  input = {
    name   = "legacy-reporter"
    status = "retired-but-retained"
  }
}

resource "local_file" "inventory" {
  filename        = var.manifest_path
  content         = local.manifest_content
  file_permission = "0644"
}

