# TechKraft Senior DevOps/Infrastructure Engineer — Take-Home Assignment

- **Candidate:** Sandab Gharti GC
- **Email:** sandabgc26@gmail.com
- **Submission Date:** 2026-05-03
- **Total Time Spent:** ~2.5 hours

---

## Repository Structure

```sh
/
├── Access-EC2-Shell.md                # Steps to access EC2 via SSM / SSH troubleshooting
├── Assets                             # Screenshots and supporting images
│   ├── EC2-homepage_us-east-1a.png            # App UI screenshot for us-east-1a
│   └── EC2-homepage_us-east-1b.png            # App UI screenshot for us-east-1b

├── part1-terraform                    # Infrastructure analysis (Part 1)
│   └── analysis.md                    # Review of Terraform setup and improvements

├── part2-linux                        # Linux & containerization tasks
│   ├── part2A-ssh-troubleshooting     # SSH debugging and fixes
│   │   └── troubleshooting.md         # Root cause + resolution steps
│   └── part2B-Dockerization           # App containerization
│       ├── app.py                     # Sample Python app
│       ├── Dockerfile                 # Docker build instructions
│       ├── dockerization.md           # Explanation of containerization
│       └── requirements.txt           # Python dependencies

├── part3-python                       # Python automation (EC2 monitoring)
│   ├── config.json                    # Config for regions and thresholds
│   ├── ec2_monitor.py                 # EC2 CPU monitoring script
│   ├── report.json                    # Generated output report
│   └── requirements.txt               # Python dependencies (boto3 etc.)

├── part4-bash                         # Bash scripting task
│   ├── analyze_nginx_logs.sh          # Nginx log analyzer script
│   └── sample-output.md               # Example output of script

├── part5-network                      # Network architecture design
│   └── architecture.md                # DNS + failover architecture (Route53)

├── part6-cicd                         # CI/CD improvements
│   └── improvements.md                # Suggested pipeline enhancements

├── part7-k8s(Optional)                # Kubernetes deployment (optional)
│   ├── Manifest-Files                 # K8s YAML manifests
│   │   ├── cm.yaml                    # ConfigMap
│   │   ├── deployment.yaml            # App deployment
│   │   ├── hpa.yaml                   # Horizontal Pod Autoscaler
│   │   ├── ns.yaml                    # Namespace definition
│   │   ├── pdb.yaml                   # Pod Disruption Budget
│   │   ├── secrets.yaml               # Kubernetes secrets
│   │   └── service.yaml               # Service exposure
│   └── Setup.md                       # Setup and deployment steps

├── ReadMe.md                          # Main project overview and instructions
├── Terraform-Cleanup.md               # Cleanup / destroy steps
├── Terraform-Setup.md                 # Setup instructions for Terraform

├── Terraform-Files(Optional)          # Full Terraform implementation
│   ├── backend.tf                     # Remote state backend config
│   ├── compute.tf                     # EC2 / ALB resources
│   ├── database.tf                    # RDS configuration
│   ├── iam.tf                         # IAM roles and policies
│   ├── main.tf                        # Root Terraform entrypoint
│   ├── modules                        # Reusable Terraform modules
│   │   ├── compute                    # Compute module
│   │   │   ├── main.tf
│   │   │   ├── outputs.tf
│   │   │   └── variables.tf
│   │   ├── database                   # Database module
│   │   │   ├── main.tf
│   │   │   ├── outputs.tf
│   │   │   └── variables.tf
│   │   ├── iam                        # IAM module
│   │   │   ├── main.tf
│   │   │   ├── outputs.tf
│   │   │   └── variables.tf
│   │   ├── secrets                    # Secrets Manager module
│   │   │   ├── main.tf
│   │   │   ├── outputs.tf
│   │   │   └── variables.tf
│   │   └── vpc                        # VPC networking module
│   │       ├── main.tf
│   │       ├── outputs.tf
│   │       └── variables.tf
│   ├── outputs.tf                     # Root outputs
│   ├── secrets.tf                     # Secrets integration
│   ├── terraform.tfvars               # Actual variable values
│   ├── terraform.tfvars.example       # Example config template
│   ├── variables.tf                   # Input variables
│   └── vpc.tf                         # VPC resource definitions

19 directories, 54 files
```

---

## Part-by-Part Summary

### Part 1: Terraform Analysis (~30 min)
- Identified **8 security issues** and **7 architectural problems** in the provided Terraform code. 
- Key findings: 
    - Hardcoded DB password
    - SSH open to 0.0.0.0/0
    - Missing security group attachment on EC2 instances
    - No private subnets
    - Single-AZ RDS with backups disabled
    - No remote state backend. See [`part1-terraform/analysis.md`](part1-terraform/analysis.md).

### Part 2: Linux Administration (~25 min)
- **Troubleshooting:** Structured 5-step diagnosis — network connectivity (`ping`/`nc`/`traceroute`), SSH daemon status via SSM, Security Group/iptables/fail2ban checks, resource utilization (top/iostat/dmesg), and log analysis (journalctl/auth.log/console output). See [`part2-linux/part2A-ssh-troubleshooting/troubleshooting.md`](part2-linux/part2A-ssh-troubleshooting/troubleshooting.md).
- **Dockerfile:** Multi-stage build with `python:3.11-alpine` builder and production stages, non-root user (uid 1001), read-only filesystem, gunicorn for production serving, and Docker HEALTHCHECK. See [`part2-linux/part2B-Dockerization/Dockerfile`](part2-linux/part2B-Dockerization/Dockerfile).

### Part 3: Python Scripting (~30 min)
-  Full `ec2_monitor.py` with: boto3 paginated EC2 listing, CloudWatch CPUUtilization metrics (last 1hr, 5-min intervals), multi-region support, JSON report generation, configurable threshold alerting, proper logging with levels, full type hints, and `argparse` CLI (`--region`, `--threshold`, `--output`, `--config`, `--log-level`). Exit code 2 when threshold exceeded (pipeline-friendly). See [`part3-python/ec2_monitor.py`](part3-python/ec2_monitor.py).

### Part 4: Bash Scripting (~20 min)
- `analyze_nginx_logs.sh` uses only `awk/sed/sort/uniq`, no external tools. Auto-detects log format field positions, gracefully skips malformed lines, calculates 4xx/5xx percentages, produces formatted table output for top IPs and endpoints. See [`part4-bash/analyze_nginx_logs.sh`](part4-bash/analyze_nginx_logs.sh).

### Part 5: Network Architecture (~20 min)
- Designed a Route 53-based hybrid DNS architecture eliminating the Unbound EC2 SPOF. Key components: Public Hosted Zone with health check failover, Private Hosted Zone for internal service discovery, Resolver Inbound/Outbound Endpoints for on-prem (Proxmox/pfSense) integration, latency-based routing to ap-south-1 (Mumbai) for Nepal users, rough cost estimate (~$10–366/month depending on hybrid requirements). See [`part5-network/architecture.md`](part5-network/architecture.md).

### Part 6: CI/CD Review (~15 min)
- Identified 6 problems (no environments, no security scanning, no secrets management, no rollback, no caching, single-stage testing). Proposed a full production pipeline: OIDC-based AWS auth, security scanning (pip-audit/bandit/Trivy/truffleHog), unit+integration tests with MySQL service container, Docker build with SBOM, auto-deploy to staging, manual approval gate for production, automatic rollback on failure, Slack notifications. See [`part6-cicd/improvements.md`](part6-cicd/improvements.md).

### Bonus: Kubernetes (~not timed)
- Complete production-grade manifests including Deployment (rolling update, liveness/readiness/startup probes, resource limits, read-only filesystem, non-root user, topology spread constraints), Service (ClusterIP + NLB annotation), HorizontalPodAutoscaler (CPU+memory metrics, scale-up/down stabilization), PodDisruptionBudget (min 1 available during drains). See [`part7-k8s(Optional)/Manifest-Files`](./part7-k8s(Optional)/Manifest-Files).

---

## Key Assumptions

1. **AWS authentication:** `ec2_monitor.py` assumes AWS credentials are available via instance profile, environment variables, or `~/.aws/credentials` (standard boto3 credential chain).
2. **Nginx log format:** The bash script handles both combined and common log formats via auto-detection.
3. **Nepal latency:** Recommended ap-south-1 (Mumbai) for the South Asia latency routing; CloudFront PoP in Mumbai serves Nepal with ~40-70ms vs 200ms+ to us-east-1.
4. **Kubernetes:** Manifests assume an AWS EKS cluster with AWS Load Balancer Controller installed for the NLB annotation.
5. **CI/CD:** Proposed pipeline assumes migration from raw EC2 rsync to containerized ECS deployment. For teams still on EC2, the same OIDC + approval gate + rollback pattern applies with `aws deploy` (CodeDeploy) instead of `aws ecs`.

---

## Tools & Versions Used

| Tool | Version |
|---|---|
| Python | 3.11+ |
| boto3 | 1.34+ |
| Terraform | ~1.7 (HCL syntax) |
| Docker | 24+ (multi-stage build) |
| Bash | 5.x |
| GitHub Actions | v4 runners |
| Kubernetes | 1.34+ (autoscaling/v2 API) |

---

## Nepal-Specific Considerations

- **Latency:** Route traffic through ap-south-1 (Mumbai) for Nepal users. CloudFront with a Mumbai origin brings API latency from ~250ms to ~50ms.
- **Timezone:** Nepal Standard Time (UTC+5:45) deploy maintenance windows should be scheduled for 10pm-4am NPT (4:15pm-10:15pm UTC) to minimize business impact.
- **Internet reliability:** Nepal's internet infrastructure can be less reliable than US/EU. Design for graceful degradation: cache aggressively at CloudFront, use exponential backoff in clients, and ensure health check failover TTLs are 60 seconds or less.
- **Team:** 11 engineers in a growing team invest in runbooks, blameless postmortems, and pair on-call rotations with UTC+5:45 awareness for incident response SLAs.


---

> Note: As you finish going through all the task, you can continue reading to [Terraform-Setup,md](./Terraform-Setup.md) to provision these resources in AWS.