variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "public_subnets" {
  description = "Public subnet IDs"
  type        = list(string)
}

variable "private_ec2_subnet_ids" {
  description = "Private EC2 subnets for ASG instances"
  type        = list(string)
}

# variable "private_db_subnet_ids" {
#   description = "Private DB subnets for RDS instances"
#   type        = list(string)
# }

variable "instance_profile" {
  description = "IAM instance profile name"
  type        = string
}

variable "instance_type" {
  type    = string
  default = "t3.micro"
}

variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "db_secret_arn" {
  description = "ARN of the Secrets Manager secret containing DB credentials"
  type        = string
}

variable "db_endpoint" {
  description = "RDS endpoint (host:port) from the database module output"
  type        = string
}
