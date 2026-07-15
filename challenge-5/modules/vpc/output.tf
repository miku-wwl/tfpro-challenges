output "subnet_ids" {
  value = [
    for subnet in aws_subnet.challenge_5 : subnet.id
  ]
}