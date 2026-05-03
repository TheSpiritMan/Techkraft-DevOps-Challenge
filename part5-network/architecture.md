# Part 5: Redundant DNS Architecture for TechKraft

## Current Problem

A single Unbound DNS server on one EC2 instance is a critical SPOF. If that instance crashes, reboots for patching, or loses networking, **all DNS resolution fails** — every service goes down simultaneously.

---

## Proposed Architecture

### Overview

Replace the single EC2-based Unbound with a **hybrid Route 53 + Resolver Endpoints** architecture:

```
                         ┌─────────────────────────────────────────┐
                         │            AWS Account                  │
                         │                                         │
  Internet Users ───────►│  Route 53 Public Hosted Zone            │
  (techkraft.com)        │  ├── A/AAAA records (ALB, API, etc.)    │
                         │  ├── Health Checks → Failover routing   │
                         │  └── Latency-based routing (South Asia) │
                         │                                         │
  On-Prem / VPN ────────►│  Route 53 Resolver Inbound Endpoints    │
(internal.techkraft.com) │  ├── ENI in AZ-a (e.g. 10.0.3.10)       │
                         │  └── ENI in AZ-b (e.g. 10.0.4.10)       │
                         │         │                               │
                         │         ▼                               │
                         │  Route 53 Private Hosted Zone           │
                         │  (internal.techkraft.com)               │
                         │  ├── db.internal → RDS endpoint         │
                         │  ├── cache.internal → ElastiCache       │
                         │  └── api.internal → ALB private DNS     │
                         │                                         │
                         │  Route 53 Resolver Outbound Endpoints   │
                         │  └── Forward rules → pfSense/FreeRAD    │
                         └─────────────────────────────────────────┘
                                      │
                         ┌────────────▼─────────────┐
                         │    On-Premises           │
                         │  pfSense DNS Forwarder   │
                         │  ├── proxmox.local       │
                         │  └── corp.techkraft      │
                         └──────────────────────────┘
```

---

## Key Components and Their Purposes

### 1. Route 53 Public Hosted Zone (`techkraft.com`)
- **Managed service** — no EC2 required, no patching, 100% SLA by AWS design
- **Globally anycast** — Route 53 nameservers are distributed across 100+ PoPs worldwide
- **Health checks with failover** — Route 53 actively monitors endpoints and updates DNS automatically

### 2. Route 53 Latency-Based Routing (for Nepal users)
- Route 53 can route `api.techkraft.com` to the **ap-south-1 (Mumbai)** edge or CloudFront origin closest to Kathmandu
- Nepal to Mumbai latency is typically 40–70ms vs. 200ms+ to `us-east-1`
- **Implementation**: Add a latency-based A record targeting CloudFront or an ALB in `ap-south-1`

### 3. Route 53 Resolver Inbound Endpoints (replaces internal Unbound)
- Two ENIs across two AZs — AWS manages redundancy automatically
- VPC instances query the VPC +2 resolver (e.g. `10.0.0.2`) which forwards to Resolver
- EC2 instances, ECS tasks, and Lambda functions all get DNS automatically

### 4. Route 53 Private Hosted Zone (`internal.techkraft.com`)
- Internal service discovery: `db.internal.techkraft.com → RDS endpoint`
- Decouples application config from IP addresses (swap RDS without changing app configs)
- Associated to the VPC; invisible from the internet

### 5. Route 53 Resolver Outbound Endpoints + Forwarding Rules
- For queries like `proxmox.local` or `corp.techkraft.com` that need to go to on-prem `pfSense`
- Rules: forward `*.corp.techkraft.com` to pfSense IP `192.168.1.1`
- Fully replaces the need for Unbound as a forwarder

---

## Failover Logic and Health Checks

### Public DNS Failover (Active-Passive)
```
Route 53 Health Check:
  Protocol:  HTTPS
  Endpoint:  api.techkraft.com/health
  Interval:  30 seconds
  Threshold: 3 consecutive failures → mark unhealthy
  SNI:       enabled

Failover routing:
  PRIMARY:  ALB in us-east-1 (or ap-south-1 for Nepal latency)
  SECONDARY: Static S3 maintenance page OR secondary region ALB
  TTL:      60 seconds (fast failover, low cache window)
```

### Internal DNS Redundancy
- Route 53 Resolver Inbound Endpoints: 2 ENIs in separate AZs
- If AZ-a fails, all DNS queries automatically route through AZ-b ENI
- No configuration change or manual intervention needed

### RDS DNS Failover
- Use RDS Multi-AZ → the CNAME endpoint (e.g., `techkraft-db.xxxxx.rds.amazonaws.com`) automatically updates during failover
- With Route 53 private hosted zone alias record pointing to the RDS endpoint, failover is transparent

---

## Latency Considerations for South Asia (Nepal)

| Approach | Nepal Latency | Cost | Complexity |
|---|---|---|---|
| Route 53 only (us-east-1) | 200–300ms DNS lookup | Low | Low |
| Route 53 latency routing → ap-south-1 | 40–70ms DNS | Medium | Low |
| Route 53 + CloudFront (Mumbai PoP) | 10–30ms DNS | Medium | Medium |
| Route 53 + Global Accelerator | 5–20ms anycast | Higher | Medium |

**Recommended for TechKraft Nepal:** Route 53 latency-based routing pointing to CloudFront with ap-south-1 as the origin. CloudFront has a PoP in Mumbai, which is the closest AWS edge to Kathmandu.

```hcl
# Latency-based routing example
resource "aws_route53_record" "api_latency_mumbai" {
  zone_id        = aws_route53_zone.public.zone_id
  name           = "api.techkraft.com"
  type           = "A"
  set_identifier = "mumbai"

  latency_routing_policy {
    region = "ap-south-1"
  }

  alias {
    name                   = aws_cloudfront_distribution.api.domain_name
    zone_id                = aws_cloudfront_distribution.api.hosted_zone_id
    evaluate_target_health = true
  }
}
```

---

## Rough Monthly Cost Estimate

| Component | Quantity | Unit Price | Monthly Cost |
|---|---|---|---|
| Route 53 Hosted Zone (public) | 1 | $0.50/zone | $0.50 |
| Route 53 Hosted Zone (private) | 1 | $0.50/zone | $0.50 |
| Route 53 Resolver Inbound Endpoints | 2 ENIs | $0.125/ENI/hr | ~$180 |
| Route 53 Resolver Outbound Endpoints | 2 ENIs | $0.125/ENI/hr | ~$180 |
| Route 53 DNS Queries | ~10M/month | $0.40/M | $4.00 |
| Route 53 Health Checks | 3 | $0.50/check | $1.50 |
| **Total** | | | **~$366/month** |

> **Note:** The Resolver Endpoints (~$360/month) are only needed if we need hybrid on-prem DNS integration. If the Proxmox/pfSense DNS integration isn't critical, we can skip outbound endpoints and save ~$180/month. Public + Private Hosted Zones + Health Checks alone cost under $10/month — a massive improvement over an unmonitored EC2. VPN Cost is not included in above table.

**Savings vs. current EC2 Unbound:** The t3.medium EC2 DNS server costs ~$30/month but provides zero redundancy. Route 53 public hosting adds cents per million queries with global redundancy built-in.

---

## Implementation Timeline

| Phase | Tasks | Time Estimate |
|---|---|---|
| **Phase 1 — Public DNS Migration** | Create Route 53 public hosted zone, import existing DNS records, update registrar NS records, set TTL to 60s before cutover | 1 day |
| **Phase 2 — Private DNS** | Create private hosted zone, add internal service records, associate to VPC, test resolution from EC2 | 2 days |
| **Phase 3 — Resolver Endpoints** | Deploy inbound/outbound endpoints via Terraform, configure pfSense forwarding rules, test on-prem → AWS and AWS → on-prem resolution | 2 days |
| **Phase 4 — Health Checks & Failover** | Add health checks for all public endpoints, configure failover routing policies, run chaos test (terminate primary, verify failover) | 1 day |
| **Phase 5 — Latency Routing** | Add latency-based records for ap-south-1, configure CloudFront origin, verify from Nepal using DNS lookup tools | 1 day |
| **Phase 6 — Decommission Unbound EC2** | After 1 week of stable operation, terminate the Unbound EC2, remove from security groups | 1 day |
| **Total** | | **~8 working days** |

---

## Terraform Snippet (Core Structure)

```hcl
# Public hosted zone
resource "aws_route53_zone" "public" {
  name = "techkraft.com"
}

# Private hosted zone for internal services
resource "aws_route53_zone" "internal" {
  name = "internal.techkraft.com"
  vpc {
    vpc_id = aws_vpc.main.id
  }
}

# Health check for primary API endpoint
resource "aws_route53_health_check" "api_primary" {
  fqdn              = "api.techkraft.com"
  port              = 443
  type              = "HTTPS"
  resource_path     = "/health"
  failure_threshold = 3
  request_interval  = 30

  tags = { Name = "api-primary-health-check" }
}

# Failover primary record
resource "aws_route53_record" "api_primary" {
  zone_id        = aws_route53_zone.public.zone_id
  name           = "api.techkraft.com"
  type           = "A"
  set_identifier = "primary"

  failover_routing_policy { type = "PRIMARY" }
  health_check_id = aws_route53_health_check.api_primary.id

  alias {
    name                   = aws_lb.main.dns_name
    zone_id                = aws_lb.main.zone_id
    evaluate_target_health = true
  }
}

# Failover secondary (maintenance page on S3)
resource "aws_route53_record" "api_secondary" {
  zone_id        = aws_route53_zone.public.zone_id
  name           = "api.techkraft.com"
  type           = "A"
  set_identifier = "secondary"

  failover_routing_policy { type = "SECONDARY" }

  alias {
    name                   = aws_s3_bucket_website_configuration.maintenance.website_endpoint
    zone_id                = aws_s3_bucket.maintenance.hosted_zone_id
    evaluate_target_health = false
  }
}
```