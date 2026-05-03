############################################
# Locals
############################################

locals {
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
    Module      = "secrets"
  }
}

resource "random_password" "db" {
  length  = 33
  special = false
}

############################################
# AWS Secrets Manager - Application Configuration
############################################
resource "aws_secretsmanager_secret" "db" {
  name = "${var.project_name}-db-credentials"

  tags = local.common_tags
}

############################################
# Secrets Configuration Values
############################################
resource "aws_secretsmanager_secret_version" "db" {
  secret_id = aws_secretsmanager_secret.db.id

  secret_string = jsonencode({
    username = "admin"
    password = random_password.db.result
  })
}