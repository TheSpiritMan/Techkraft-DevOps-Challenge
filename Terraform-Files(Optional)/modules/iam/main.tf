############################################
# Locals
############################################

locals {
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
    Module      = "iam"
  }
}

############################################
# EC2 IAM Role
############################################

resource "aws_iam_role" "ec2" {
  name = "techkraft-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = local.common_tags
}

############################################
# Managed Policy Attachments
############################################

# SSM Session Manager — replaces SSH, allows aws ssm start-session
resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

############################################
# Inline Policy — Least Privilege
############################################

resource "aws_iam_role_policy" "ec2_inline" {
  name = "techkraft-ec2-inline-policy"
  role = aws_iam_role.ec2.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # Allow EC2 to fetch DB credentials from Secrets Manager
      # Scoped to only the DB secret — not all secrets in the account
      {
        Sid    = "AllowSecretsManagerRead"
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = var.db_secret_arn
      }
    ]
  })
}

############################################
# Instance Profile — attached to EC2 / Launch Template
############################################

resource "aws_iam_instance_profile" "this" {
  name = "techkraft-ec2-profile"
  role = aws_iam_role.ec2.name
  tags = local.common_tags
}
