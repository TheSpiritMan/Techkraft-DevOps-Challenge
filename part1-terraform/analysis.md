# Part 1: Terraform Infrastructure Analysis

## Security Issues (6 minimum identified)

### 1. SSH Open to the World (CRITICAL)
```hcl
ingress {
  from_port   = 22
  to_port     = 22
  protocol    = "tcp"
  cidr_blocks = ["0.0.0.0/0"]  # ← Exposes SSH to the entire internet
}
```
**Fix:** Restrict SSH to our office/VPN CIDR or use AWS Systems Manager Session Manager and remove SSH entirely.
```hcl
cidr_blocks = ["13.0.0.0/8"]  # `13.0.0.0/8` being our VPN CIDR
```

### 2. Hardcoded Database Credentials in Plaintext (CRITICAL)
```hcl
username = "admin"        # ← Committed to version control
password = "changeme123"  # ← Committed to version control
```
**Fix:** Use AWS Secrets Manager or SSM Parameter Store and reference it:
```hcl
data "aws_secretsmanager_secret_version" "db" {
  secret_id = var.secret_arn
}

locals {
  creds = jsondecode(data.aws_secretsmanager_secret_version.db.secret_string)
}

resource "aws_db_instance" "this" {
  identifier = "techkraft-db"
  .....
  .....

  username = local.creds.username
  password = local.creds.password
  ....
}
```

### 3. EC2 Instances Have No Security Group Assigned
The `aws_instance.web` resource never references `aws_security_group.web`. The SG is created but never attached.
```hcl
resource "aws_instance" "web" {
  # Missing: vpc_security_group_ids = [aws_security_group.web.id]
}
```

### 4. S3 Bucket Has No Public Access Block or Encryption
```hcl
resource "aws_s3_bucket" "uploads" {
  bucket = "techkraft-uploads"
  # No: aws_s3_bucket_public_access_block
  # No: aws_s3_bucket_server_side_encryption_configuration
  # No: aws_s3_bucket_versioning
}
```
**Fix:** Add a `aws_s3_bucket_public_access_block` resource and enable SSE-S3 or SSE-KMS encryption.

### 5. Database Deletion Protection Disabled
```hcl
deletion_protection = false   # ← Production DB can be accidentally destroyed
skip_final_snapshot = true    # ← No backup taken on destruction
backup_retention_period = 0   # ← Automated backups completely disabled
```
All three together mean the production database can be permanently destroyed with zero recovery options.

### 6. RDS Using Wrong/Shared Security Group
```hcl
vpc_security_group_ids = [aws_security_group.web.id]
```
The RDS instance shares the web server's security group (which allows port 80/22 from 0.0.0.0/0). MySQL port 3306 should only be accessible from the app servers' security group, not from the internet.

### 7. No Encryption at Rest for RDS
The `aws_db_instance` has no `storage_encrypted = true`. Sensitive customer data in MySQL is stored unencrypted.

### 8. Hardcoded AMI ID
```hcl
ami = "ami-0c55b159cbfafe1f0"
```
This AMI may be outdated/unpatched. Use a `data` source to always fetch the latest approved AMI:
```hcl
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]
  filter { name = "name"; values = ["amzn2-ami-hvm-*-x86_64-gp2"] }
}
```

---

## Architectural Problems (5 minimum identified)

### 1. No Private Subnets — Everything Is Public
All EC2 and RDS instances are in public subnets (`map_public_ip_on_launch = true`). The database should never be internet-reachable. Application servers should sit behind a load balancer in private subnets.

**Correct architecture:**
```
Internet → IGW → ALB (public subnet) → EC2 (private subnet) → RDS (isolated subnet)
```

### 2. Single Point of Failure — No Load Balancer, No Auto Scaling
Three EC2 instances sit directly in public subnets with no Application Load Balancer (ALB). If one instance fails, traffic is not redistributed. There is no Auto Scaling Group (ASG) to replace failed instances.

**Fix:** Add an ALB + Target Group + ASG with health checks.

### 3. RDS Is Single-AZ With No Read Replicas
`aws_db_instance` has no `multi_az = true`. A single-AZ RDS instance causes a 1–2 minute outage during maintenance windows and is a total failure point for the database tier.

**Fix:**
```hcl
multi_az            = true
backup_retention_period = 7
```

### 4. No NAT Gateway — Private Resources Cannot Reach Internet Safely
Without private subnets and NAT gateways, instances either need public IPs (security risk) or cannot download updates/patches at all.

**Fix:** Add private subnets + NAT Gateway in each AZ:
```hcl
resource "aws_nat_gateway" "main" {
  count         = 2
  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id
}
```

### 5. Missing Outputs and State Management
- `output "web_ips"` exports private IPs but these are useless when instances are in public subnets (private IPs aren't routable externally). Should export the ALB DNS name instead.
- No `backend` block means Terraform state is stored locally — breaks team collaboration and is a data loss risk.

```hcl
terraform {
  backend "s3" {
    bucket       = "techkraft-tfstate"
    key          = "prod/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}
```

### 6. No Tagging Strategy
Resources have minimal or no tags, making cost allocation, compliance auditing, and resource identification very difficult in AWS Cost Explorer and CloudTrail.

**Fix:** Use a local for consistent tagging:
```hcl
locals {
  common_tags = {
    Project     = techkraft-devops-challenge
    Environment = prod
    ManagedBy   = "terraform"
  }
}
```

### 7. Subnet CIDR Uses count.index — Fragile Approach
```hcl
cidr_block = "10.0.${count.index}.0/24"
```
If subnets are ever reordered or count changes, Terraform will destroy/recreate subnets, taking down all instances. Use explicit `for_each` with a map instead.

---

## Production-Readiness Changes Summary

| Category | Change |
|---|---|
| **Secrets** | Move DB password to AWS Secrets Manager |
| **Network** | Add private subnets, NAT Gateways, remove public IPs from EC2/RDS |
| **Compute** | Add ALB + ASG with health checks and min/max instance counts |
| **Database** | Enable multi-AZ, automated backups (7-day retention), deletion protection, encryption at rest |
| **Security Groups** | Separate SGs per tier (ALB → App → DB), restrict SSH to VPN/bastion or AWS SSM only|
| **State** | Add S3 backend with state locking in S3 itself |
| **S3** | Enable public access block, versioning, SSE encryption |
| **Observability** | Add CloudWatch alarms for CPU, RDS connections, ALB 5xx errors |
| **Tagging** | Enforce consistent tagging via locals |
| **AMI** | Use data source for latest approved AMI |