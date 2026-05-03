variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "db_secret_arn" {
  description = "ARN of the DB credentials secret — IAM policy scoped to this only"
  type        = string
}