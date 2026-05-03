# Part 2A: Linux SSH Troubleshooting — Unresponsive Server (10.0.1.50)

## Step-by-Step Diagnosis Commands (in order)

---

### Step 1: Verify Network Connectivity from Jump Host

```bash
# Basic reachability using ICMP ping (most of the time blocked by security group)
ping -c 4 10.0.1.50

# If ping is blocked, we can try connecting to TCP port of SSH i.e 22
nc -zv 10.0.1.50 22
# Or with timeout:
timeout 5 bash -c 'cat < /dev/null > /dev/tcp/10.0.1.50/22' && echo "Port open" || echo "Port closed/filtered"

# Traceroute to identify where packets stop
traceroute 10.0.1.50
# Or mtr for continuous monitoring:
mtr --report 10.0.1.50

# Check if it's a DNS/ARP issue (if on same subnet)
arp -n 10.0.1.50
```

**What to look for:** If ping fails completely, the issue is likely at the network/firewall layer (AWS Security Group, NACLs, or the instance itself is down). If ping succeeds but SSH times out, SSH daemon is the problem.

---

### Step 2: Check if SSH Service Is Running (once network confirmed working)

```bash
# From AWS Console: Use EC2 Serial Console or Systems Manager Session Manager
# to get shell access without SSH

# Via SSM Session Manager (if agent is installed):
aws ssm start-session --target i-INSTANCEID --region us-east-1

# Once inside the instance, check SSH daemon:
sudo systemctl status sshd
sudo systemctl status ssh       # Debian/Ubuntu naming

# Check if sshd process exists:
ps aux | grep sshd

# Check what port SSH is actually listening on:
sudo ss -tlnp | grep ssh
sudo netstat -tlnp | grep :22

# Try restarting if stopped:
sudo systemctl restart sshd
```

---

### Step 3: SSH Running But Still Can't Connect — Possible Causes

```bash
# 1. Check AWS Security Group from jump host (or via CLI):
aws ec2 describe-security-groups \
  --filters "Name=ip-permission.from-port,Values=22" \
  --query "SecurityGroups[*].{ID:GroupId,Rules:IpPermissions}"

# 2. Check AWS Network ACLs — stateless, can block return traffic:
aws ec2 describe-network-acls --query "NetworkAcls[*].Entries"

# 3. On the instance — check if hosts.deny or TCP wrappers are blocking:
sudo cat /etc/hosts.deny
sudo cat /etc/hosts.allow

# 4. Check if fail2ban or iptables is blocking our IP:
sudo iptables -L INPUT -n -v | grep DROP
sudo fail2ban-client status sshd
sudo fail2ban-client set sshd unbanip <OUR_JUMP_HOST_IP>

# 5. Check SSH known_hosts / key mismatch on our client:
ssh -v -i ~/.ssh/key.pem ubuntu@10.0.1.50  # -v for verbose output
# Look for: "Permission denied (publickey)" vs timeout vs connection refused

# 6. Check sshd_config for restrictions:
sudo cat /etc/ssh/sshd_config | grep -E "AllowUsers|DenyUsers|AllowGroups|MaxAuthTries|PasswordAuthentication"

# 7. Check if the filesystem is full (can prevent sshd from writing temp files):
df -h
```

**Common causes summary:**
| Symptom | Likely Cause |
|---|---|
| `Connection timed out` | Security Group, NACL, or iptables blocking port 22 |
| `Connection refused` | sshd not running or listening on different port |
| `Permission denied (publickey)` | Wrong key, wrong user, or `authorized_keys` permissions wrong |
| `Too many authentication failures` | fail2ban banned our IP |

---

### Step 4: Check CPU, Memory, and Disk Usage

```bash
# CPU — top processes consuming CPU:
top -b -n 1 | head -20
# Or more readable:
ps aux --sort=-%cpu | head -15

# Memory — RAM and swap usage:
free -h
vmstat -s
# Top memory consumers:
ps aux --sort=-%mem | head -15

# Disk — overall usage:
df -hT

# Disk I/O — check if disk is saturated (could cause SSH timeouts):
iostat -xz 1 5
# Or:
iotop -b -n 3  # iotop can be installed using `sudo apt install iotop -y`

# Check for processes in D state (uninterruptible sleep = disk/IO wait):
ps aux | awk '$8 == "D"'

# Inode exhaustion (can make disk appear full when df shows space):
df -i

# AWS CloudWatch metrics (from jump host, for the last hour):
aws cloudwatch get-metric-statistics \
  --namespace AWS/EC2 \
  --metric-name CPUUtilization \
  --dimensions Name=InstanceId,Value=i-INSTANCEID \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Average
```

---

### Step 5: Check Recent System Logs for Errors

```bash
# Systemd journal — last 200 lines, show errors:
sudo journalctl -xe --no-pager | tail -100
sudo journalctl -p err -b    # Errors since last boot
sudo journalctl -p err --since "1 hour ago"

# Kernel ring buffer — hardware/kernel errors, OOM killer:
sudo dmesg -T | tail -50
sudo dmesg -T | grep -E "OOM|kill|error|fail|panic" -i

# Auth log — failed SSH logins, sudo abuse:
sudo tail -100 /var/log/auth.log        # Debian/Ubuntu
sudo tail -100 /var/log/secure          # RHEL/CentOS/Amazon Linux

# System log:
sudo tail -100 /var/log/syslog          # Debian/Ubuntu
sudo tail -100 /var/log/messages        # RHEL/CentOS

# Application logs (if this is a web server):
sudo tail -50 /var/log/nginx/error.log
sudo tail -50 /var/log/nginx/access.log

# Check for OOM kill events specifically:
sudo dmesg -T | grep -i "out of memory"
sudo grep -i "killed process" /var/log/syslog

# AWS instance console output (available via CLI even if SSH is down):
aws ec2 get-console-output --instance-id i-INSTANCEID --output text
```

**Key things to look for in logs:**
- OOM killer events (process killed due to memory exhaustion) → scale up instance or fix memory leak
- Kernel panic or hardware errors → contact AWS support, replace instance
- Disk full errors → expand EBS volume or clean up logs
- SSH authentication failures flood → brute-force attack, consider fail2ban tuning
- Service crash loops → check application health