############################################
# Locals
############################################

locals {
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
    Module      = "database"
  }
}


data "aws_secretsmanager_secret_version" "db" {
  secret_id = var.db_secret_arn
}

locals {
  creds = jsondecode(data.aws_secretsmanager_secret_version.db.secret_string)
}

resource "aws_db_subnet_group" "this" {
  name       = "${var.project_name}-db-subnet-group"
  subnet_ids = var.private_db_subnet_ids
}

resource "aws_security_group" "db" {
  name        = "techkraft-db-sg"
  description = "Allow MySQL access from app servers only"
  vpc_id     = var.vpc_id

  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [var.app_sg_id]
  }

  tags = merge(local.common_tags, {
    Name = "techkraft-db-sg"
  })
}

resource "aws_db_instance" "this" {
  identifier = "techkraft-db"

  engine         = "mysql"
  instance_class = "db.t3.micro"        # free tier eligible instance type

  allocated_storage = 20

  username = local.creds.username
  password = local.creds.password

  multi_az                = false # must be true but for now required for free tier eligibility
  storage_encrypted       = true
  backup_retention_period = 1 # must be 7 but for now no backups for free tier

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.db.id]

  skip_final_snapshot = true  # must be false but for now we don't want to create a snapshot on deletion
}

