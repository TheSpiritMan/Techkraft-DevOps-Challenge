output "db_secret_arn" {
  description = "ARN of the DB credentials secret in Secrets Manager"
  value       = aws_secretsmanager_secret.db.arn
}

output "db_secret_name" {
  description = "Name of the DB credentials secret in Secrets Manager"
  value       = aws_secretsmanager_secret.db.name
}