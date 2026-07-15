locals {
  manifest = jsondecode(file(var.manifest_path))
}

# TODO 1: 弱类型安全地规范化 manifest header 与 artifacts。
# TODO 2: 分别检查 header、非空列表、name 唯一性、object key 唯一性、字段和 enabled 集合。
# TODO 3: 计算不受 artifacts 数组顺序影响的 canonical manifest SHA-256。
# TODO 4: 创建唯一、可安全销毁并带规范标签的 aws_s3_bucket.release。
# TODO 5: 以 artifact name 为 for_each key 创建 aws_s3_object.artifact，完整声明内容、etag、metadata 与 tags。
