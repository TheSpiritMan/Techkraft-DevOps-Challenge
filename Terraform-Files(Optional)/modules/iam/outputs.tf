output "instance_profile" {
  value = aws_iam_instance_profile.this.name
}


output "ec2_role_arn" {
  description = "ARN of the EC2 IAM role"
  value       = aws_iam_role.ec2.arn
}