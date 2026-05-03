############################################
# VPC ID
############################################

output "vpc_id" {
  value = aws_vpc.this.id
}

############################################
# Public Subnets
############################################

output "public_subnets" {
  description = "Map of public subnets per AZ"
  value = {
    for k, v in aws_subnet.public : k => v.id
  }
}

output "public_subnet_ids" {
  description = "List of public subnet IDs"
  value       = values(aws_subnet.public)[*].id
}

############################################
# Private EC2 Subnets
############################################

output "private_ec2_subnets" {
  description = "Map of private EC2 subnets per AZ"
  value = {
    for k, v in aws_subnet.private_ec2 : k => v.id
  }
}

output "private_ec2_subnet_ids" {
  description = "List of private EC2 subnet IDs"
  value       = values(aws_subnet.private_ec2)[*].id
}

############################################
# Private DB Subnets
############################################

output "private_db_subnets" {
  description = "Map of private DB subnets per AZ"
  value = {
    for k, v in aws_subnet.private_db : k => v.id
  }
}

output "private_db_subnet_ids" {
  description = "List of private DB subnet IDs"
  value       = values(aws_subnet.private_db)[*].id
}

############################################
# NAT Gateways
############################################

output "nat_gateways" {
  description = "NAT Gateway details per AZ"
  value = {
    for k, v in aws_nat_gateway.nat : k => {
      id        = v.id
      public_ip = aws_eip.nat[k].public_ip
      subnet_id = v.subnet_id
    }
  }
}