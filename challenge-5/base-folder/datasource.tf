data "aws_vpc" "random" {
  filter {
    name   = "tag:Name"
    values = ["challenge-5-vpc"]
  }
}

data "aws_subnets" "random" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.random.id]
  }

  filter {
    name   = "tag:Name"
    values = ["subnet-subnet1", "subnet-subnet2"]
  }
}

output "subnet_ids" {
  value = data.aws_subnets.random.ids
}