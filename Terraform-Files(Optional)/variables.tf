variable "aws_region" {
  default = "us-east-1"
}

variable "project_name" {
  default = "techkraft"
}

variable "environment" {
  default = "prod"
}

variable "vpc_cidr" {
  default = "10.0.0.0/16"
}

variable "az_count" {
  type    = number
  default = 2
}