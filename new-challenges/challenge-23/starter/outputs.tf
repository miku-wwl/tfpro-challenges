# TODO: 用一个带 schema_version 的 network_v2 对象替代 v1 松散接口。
output "vpc_id" {
  value = aws_vpc.main[0].id
}

output "subnet_ids" {
  value = aws_subnet.this[*].id
}

output "security_group_ids" {
  value = aws_security_group.this[*].id
}
