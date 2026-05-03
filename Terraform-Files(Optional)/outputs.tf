############################################
# Secrets Outputs
############################################
output "db_secret_arn" {
  value = module.secrets.db_secret_arn
}

############################################
# VPC Outputs
############################################

output "vpc_id" {
  value = module.vpc.vpc_id
}

# Public Subnets
output "public_subnets" {
  value = module.vpc.public_subnets
}

# Private EC2 Subnets
output "private_ec2_subnets" {
  value = module.vpc.private_ec2_subnet_ids
}

# Private DB Subnets
output "private_db_subnets" {
  value = module.vpc.private_db_subnet_ids
}

output "nat_gateways" {
  value = module.vpc.nat_gateways
}

############################################
# IAM Outputs
############################################

output "instance_profile" {
  value = module.iam.instance_profile
}

output "ec2_role_arn" {
  value = module.iam.ec2_role_arn
}


############################################
# Compute Outputs
############################################

output "alb_dns" {
  value = module.compute.alb_dns
}

############################################
# Database Outputs
############################################
output "db_endpoint" {
  value = module.database.db_endpoint
}