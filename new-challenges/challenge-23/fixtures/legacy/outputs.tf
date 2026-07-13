output "vpc_id" {
  value = aws_vpc.main[0].id
}

output "subnet_ids" {
  value = aws_subnet.this[*].id
}

output "security_group_ids" {
  value = aws_security_group.this[*].id
}
