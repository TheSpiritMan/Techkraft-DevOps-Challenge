############################################
# Data Sources
############################################

data "aws_availability_zones" "azs" {
  state = "available"
}

############################################
# Locals
############################################

locals {
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
    Module      = "vpc"
  }

  az_list = data.aws_availability_zones.azs.names

  azs = slice(
    local.az_list,
    0,
    min(var.az_count, length(local.az_list))
  )

  az_map = {
    for idx, az in local.azs :
    "az${idx + 1}" => az
  }
}

############################################
# VPC
############################################

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(local.common_tags, {
    Name = "techkraft-vpc"
  })
}

############################################
# Internet Gateway
############################################

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.this.id

  tags = merge(local.common_tags, {
    Name = "techkraft-igw"
  })
}

############################################
# Public Subnets
############################################

resource "aws_subnet" "public" {
  for_each = local.az_map

  vpc_id                  = aws_vpc.this.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, index(keys(local.az_map), each.key))
  availability_zone       = each.value
  map_public_ip_on_launch = true

  tags = merge(local.common_tags, {
    Name = "public-${each.key}"
  })
}

############################################
# Private EC2 Subnets
############################################

resource "aws_subnet" "private_ec2" {
  for_each = local.az_map

  vpc_id            = aws_vpc.this.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, index(keys(local.az_map), each.key) + 10)
  availability_zone = each.value

  tags = merge(local.common_tags, {
    Name = "private-ec2-${each.key}"
  })
}

############################################
# Private DB Subnets (Isolated Tier)
############################################

resource "aws_subnet" "private_db" {
  for_each = local.az_map

  vpc_id            = aws_vpc.this.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, index(keys(local.az_map), each.key) + 20)
  availability_zone = each.value

  tags = merge(local.common_tags, {
    Name = "private-db-${each.key}"
  })
}

############################################
# NAT Gateway
############################################

resource "aws_eip" "nat" {
  for_each = local.az_map

  tags = merge(local.common_tags, {
    Name = "nat-eip-${each.key}"
  })
}

resource "aws_nat_gateway" "nat" {
  for_each = local.az_map

  allocation_id = aws_eip.nat[each.key].id
  subnet_id     = aws_subnet.public[each.key].id

  tags = merge(local.common_tags, {
    Name = "nat-${each.key}"
  })

  depends_on = [aws_internet_gateway.igw]
}

############################################
# Route Tables
############################################

# Public Route Table
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  tags = merge(local.common_tags, {
    Name = "public-rt"
  })
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.igw.id

  depends_on = [aws_internet_gateway.igw]
}

############################################
# Private Route Tables (per AZ)
############################################

resource "aws_route_table" "private_ec2" {
  for_each = local.az_map

  vpc_id = aws_vpc.this.id

  tags = merge(local.common_tags, {
    Name = "private-ec2-rt-${each.key}"
  })
}

############################################
# DB Route Tables (NO NAT, NO INTERNET)
############################################

resource "aws_route_table" "private_db" {
  for_each = local.az_map

  vpc_id = aws_vpc.this.id

  tags = merge(local.common_tags, {
    Name = "private-db-rt-${each.key}"
  })
}

resource "aws_route" "private_ec2_nat" {
  for_each = local.az_map

  route_table_id         = aws_route_table.private_ec2[each.key].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.nat[each.key].id
}

############################################
# Route Table Associations
############################################

resource "aws_route_table_association" "public" {
  for_each = local.az_map

  subnet_id      = aws_subnet.public[each.key].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private_ec2" {
  for_each = local.az_map

  subnet_id      = aws_subnet.private_ec2[each.key].id
  route_table_id = aws_route_table.private_ec2[each.key].id
}

resource "aws_route_table_association" "private_db" {
  for_each = local.az_map

  subnet_id      = aws_subnet.private_db[each.key].id
  route_table_id = aws_route_table.private_db[each.key].id
}