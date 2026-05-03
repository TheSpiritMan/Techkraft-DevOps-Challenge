############################################
# Locals
############################################

locals {
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
    Module      = "compute"
  }
}

data "aws_ami" "al2" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*"]
  }
}

resource "aws_security_group" "alb" {
  name        = "techkraft-alb-sg"
  description = "Allow HTTP access from the internet"
  vpc_id     = var.vpc_id

  ingress {
    from_port = 80
    to_port   = 80
    protocol  = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "techkraft-alb-sg"
  })
}

resource "aws_security_group" "app" {
  name        = "techkraft-app-sg"
  description = "Allow HTTP access from ALB"
  vpc_id     = var.vpc_id

  ingress {
    from_port       = 5000
    to_port         = 5000
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]   # SSM, EC2 messages, S3 endpoints
  }
  
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]   # Allow all outbound
  }

  tags = merge(local.common_tags, {
    Name = "techkraft-app-sg"
  })
}

resource "aws_lb" "this" {
  name               = "techkraft-alb"
  load_balancer_type = "application"
  subnets            = var.public_subnets
  security_groups    = [aws_security_group.alb.id]

  tags = merge(local.common_tags, {
    Name = "techkraft-alb"
  })

}

resource "aws_lb_target_group" "this" {
  name     = "techkraft-app-tg"
  port     = 5000
  protocol = "HTTP"
  vpc_id   = var.vpc_id

  health_check {
    path = "/health"
  }

  tags = merge(local.common_tags, {
    Name = "techkraft-app-tg"
  })
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  tags              = local.common_tags

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this.arn
  }
}

resource "aws_launch_template" "app" {
  name          = "techkraft-app-launch-template"
  image_id      = data.aws_ami.al2.id
  instance_type = var.instance_type
  tags          = local.common_tags

  iam_instance_profile {
    name = var.instance_profile
  }

  vpc_security_group_ids = [aws_security_group.app.id]

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  user_data = base64encode(<<-EOF
  #!/bin/bash
  set -euo pipefail
  yum install -y https://dev.mysql.com/get/mysql80-community-release-el7-7.noarch.rpm || true
  rpm --import https://repo.mysql.com/RPM-GPG-KEY-mysql-2023 || true
  yum install -y amazon-ssm-agent mysql-community-client --nogpgcheck
  systemctl enable amazon-ssm-agent
  systemctl start amazon-ssm-agent

  TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" \
    -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")

  INTERNAL_IP=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
    http://169.254.169.254/latest/meta-data/local-ipv4)

  AZ=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
    http://169.254.169.254/latest/meta-data/placement/availability-zone)

  INSTANCE_ID=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
    http://169.254.169.254/latest/meta-data/instance-id)

  INSTANCE_TYPE=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
    http://169.254.169.254/latest/meta-data/instance-type)

  REGION=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
    http://169.254.169.254/latest/meta-data/placement/region)

  SECRET_JSON=$(aws secretsmanager get-secret-value \
    --secret-id "${var.db_secret_arn}" \
    --region "$REGION" \
    --query SecretString \
    --output text)

  DB_USER=$(echo "$SECRET_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin)['username'])")
  DB_PASS=$(echo "$SECRET_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin)['password'])")

  DB_ENDPOINT="${var.db_endpoint}"
  DB_HOST=$(echo "$DB_ENDPOINT" | cut -d':' -f1)
  DB_PORT=$(echo "$DB_ENDPOINT" | cut -d':' -f2)

  if mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASS" \
       --connect-timeout=5 -e "SELECT 1;" > /dev/null 2>&1; then
    DB_STATUS="Connected"
  else
    DB_STATUS="Failed"
  fi

  mkdir -p /opt/techkraft

  # ↓↓ No leading spaces — starts at column 0 ↓↓
  cat > /opt/techkraft/server.py << 'PYEOF'
  import http.server
  import json
  import os
  import subprocess

  INTERNAL_IP   = os.environ["INTERNAL_IP"]
  AZ            = os.environ["AZ"]
  INSTANCE_ID   = os.environ["INSTANCE_ID"]
  INSTANCE_TYPE = os.environ["INSTANCE_TYPE"]
  DB_HOST       = os.environ["DB_HOST"]
  DB_PORT       = os.environ["DB_PORT"]
  DB_USER       = os.environ["DB_USER"]
  DB_PASS       = os.environ["DB_PASS"]

  def check_db():
      try:
          result = subprocess.run(
              ["mysql", "-h", DB_HOST, "-P", DB_PORT,
               "-u", DB_USER, f"-p{DB_PASS}",
               "--connect-timeout=5", "-e", "SELECT 1;"],
              capture_output=True, timeout=6
          )
          return ("Connected", "#22c55e") if result.returncode == 0 else ("Failed", "#ef4444")
      except Exception as e:
          return (f"Error: {e}", "#ef4444")

  class Handler(http.server.BaseHTTPRequestHandler):

      def do_GET(self):
          if self.path == "/health":
              body = json.dumps({"status": "healthy"}).encode()
              self.send_response(200)
              self.send_header("Content-Type", "application/json")
              self.send_header("Content-Length", len(body))
              self.end_headers()
              self.wfile.write(body)

          elif self.path == "/":
              db_status, db_color = check_db()
              body = f"""<!DOCTYPE html>
  <html>
  <head>
      <title>TechKraft</title>
      <style>
          * {{ box-sizing: border-box; margin: 0; padding: 0; }}
          body  {{ font-family: Arial, sans-serif; background: #0f172a;
                  color: #e2e8f0; display: flex; flex-direction: column;
                  align-items: center; padding: 60px 20px; }}
          h1    {{ color: #38bdf8; font-size: 28px; }}
          p     {{ color: #64748b; margin-top: 6px; font-size: 14px; }}
          .card {{ background: #1e293b; border-radius: 12px; margin-top: 30px;
                  width: 100%; max-width: 540px; overflow: hidden; }}
          .section-title {{ background: #0f172a; color: #38bdf8; font-size: 11px;
                            font-weight: bold; letter-spacing: 1px;
                            text-transform: uppercase; padding: 10px 24px; }}
          .row  {{ display: flex; justify-content: space-between; align-items: center;
                  padding: 13px 24px; border-top: 1px solid #334155; }}
          .label {{ color: #94a3b8; font-size: 13px; }}
          .value {{ color: #f1f5f9; font-size: 14px; font-weight: bold; font-family: monospace; }}
          .badge {{ display: inline-block; border-radius: 6px; padding: 3px 14px;
                    font-size: 13px; font-weight: bold; color: #fff; background: {db_color}; }}
      </style>
  </head>
  <body>
      <h1>TechKraft API</h1>
      <p>AWS Auto Scaling Group: Instance Dashboard</p>
      <div class="card">
          <div class="section-title">Instance Info</div>
          <div class="row"><span class="label">Instance ID</span><span class="value">{INSTANCE_ID}</span></div>
          <div class="row"><span class="label">Instance Type</span><span class="value">{INSTANCE_TYPE}</span></div>
          <div class="row"><span class="label">Internal IP</span><span class="value">{INTERNAL_IP}</span></div>
          <div class="row"><span class="label">Availability Zone</span><span class="value">{AZ}</span></div>
          <div class="section-title">Database</div>
          <div class="row"><span class="label">Endpoint</span><span class="value">{DB_HOST}:{DB_PORT}</span></div>
          <div class="row"><span class="label">User</span><span class="value">{DB_USER}</span></div>
          <div class="row"><span class="label">Connection</span><span class="badge">{db_status}</span></div>
      </div>
  </body>
  </html>""".encode()
              self.send_response(200)
              self.send_header("Content-Type", "text/html")
              self.send_header("Content-Length", len(body))
              self.end_headers()
              self.wfile.write(body)

          else:
              self.send_response(404)
              self.end_headers()

      def log_message(self, format, *args):
          print(f"{self.address_string()} - {format % args}", flush=True)

  if __name__ == "__main__":
      server = http.server.HTTPServer(("0.0.0.0", 5000), Handler)
      print("Listening on :5000", flush=True)
      server.serve_forever()
  PYEOF

  # ↓↓ No leading spaces — starts at column 0 ↓↓
  cat > /etc/systemd/system/techkraft.service << SVCEOF
  [Unit]
  Description=TechKraft HTTP Server
  After=network.target

  [Service]
  User=nobody
  Environment="INTERNAL_IP=$INTERNAL_IP"
  Environment="AZ=$AZ"
  Environment="INSTANCE_ID=$INSTANCE_ID"
  Environment="INSTANCE_TYPE=$INSTANCE_TYPE"
  Environment="DB_HOST=$DB_HOST"
  Environment="DB_PORT=$DB_PORT"
  Environment="DB_USER=$DB_USER"
  Environment="DB_PASS=$DB_PASS"
  ExecStart=/usr/bin/python3 /opt/techkraft/server.py
  StandardOutput=journal
  StandardError=journal
  Restart=always
  RestartSec=5

  [Install]
  WantedBy=multi-user.target
  SVCEOF

    systemctl daemon-reload
    systemctl enable techkraft
    systemctl start techkraft
  EOF
  )

}

resource "aws_autoscaling_group" "app" {
  name             = "techkraft-app-asg"
  min_size         = 2
  max_size         = 3
  desired_capacity = 2

  vpc_zone_identifier = var.private_ec2_subnet_ids

  launch_template {
    id      = aws_launch_template.app.id
    version = "$Latest"
  }

  target_group_arns = [aws_lb_target_group.this.arn]
}