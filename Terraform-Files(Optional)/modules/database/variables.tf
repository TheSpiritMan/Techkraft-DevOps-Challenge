variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "vpc_id" {
  type = string
}

############################################
# DB Subnets (explicit)
############################################

variable "private_db_subnet_ids" {
  description = "List of private DB subnet IDs (isolated, no internet)"
  type        = list(string)
}

############################################
# App Security Group
############################################

variable "app_sg_id" {
  description = "Security group ID of application layer (allowed to access DB)"
  type        = string
}

############################################
# Secrets Manager
############################################

variable "db_secret_arn" {
  description = "Secrets Manager ARN for DB credentials"
  type        = string
}