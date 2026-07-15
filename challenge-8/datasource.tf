data "aws_subnet" "app" {
  id = "subnet-408a7d89c52c8ef43"
}

data "aws_subnet" "database" {
  id = "subnet-04e9bf4426e83d741"
}

data "aws_subnet" "central" {
  id = "subnet-2ae5f6ce88e9ec9c0"
}

output "aws_subnet_app_cidr" {
  value = data.aws_subnet.app.cidr_block
}

output "aws_subnet_database_cidr" {
  value = data.aws_subnet.database.cidr_block
}

output "aws_subnet_central_cidr" {
  value = data.aws_subnet.central.cidr_block
}

output "subnet_ids" {
  value = [{
    id   = data.aws_subnet.app.id
    name = data.aws_subnet.app.tags["Name"]
    }, {
    id = data.aws_subnet.database.id
    name = data.aws_subnet.database.tags["Name"]
    }, {
    id = data.aws_subnet.central.id
    name = data.aws_subnet.central.tags["Name"]
  }]
}