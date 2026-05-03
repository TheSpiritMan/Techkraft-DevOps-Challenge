variable "az_count" {
  description = "Number of AZs to use"
  type        = number
  default     = 2
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
}

variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}