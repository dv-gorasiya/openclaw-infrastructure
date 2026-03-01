# OpenClaw AWS Infrastructure

Terraform modules for deploying [OpenClaw](https://openclaw.ai) on AWS. Single-command deployment with automated backups, monitoring, and VPN access — running at ~$45-70/month.

## Architecture

```
┌──────────────────────────────────────────────┐
│  AWS Account                                  │
│  ┌────────────────────────────────────────┐  │
│  │  VPC (10.0.0.0/16)                     │  │
│  │  ┌──────────────────────────────────┐  │  │
│  │  │  Subnet + IGW                    │  │  │
│  │  │  ┌────────────────────────────┐  │  │  │
│  │  │  │  EC2 (ASG min=1 max=1)    │  │  │  │
│  │  │  │  - No inbound SG rules    │  │  │  │
│  │  │  │  - IMDSv2 enforced        │  │  │  │
│  │  │  │  - CloudWatch Agent       │  │  │  │
│  │  │  └──────────┬─────────────────┘  │  │  │
│  │  │             │                     │  │  │
│  │  │  ┌──────────▼─────────────────┐  │  │  │
│  │  │  │  EBS (gp3, encrypted)     │  │  │  │
│  │  │  │  Daily + weekly backups   │  │  │  │
│  │  │  └────────────────────────────┘  │  │  │
│  │  └──────────────────────────────────┘  │  │
│  │  S3 Gateway Endpoint (free)            │  │
│  └────────────────────────────────────────┘  │
│                                               │
│  Secrets Manager · CloudWatch · AWS Backup    │
│  SNS Alerts · Budget Alerts · SSM            │
└──────────────────────────────────────────────┘

Access: Tailscale VPN or SSM Session Manager (no public exposure)
```

## Quick Start

### Prerequisites

- [Terraform](https://www.terraform.io/downloads) >= 1.5
- [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) configured
- An [Anthropic API key](https://console.anthropic.com/)
- [Tailscale](https://tailscale.com/) account (optional, recommended)

### 1. Set Up Terraform State

```bash
./scripts/setup-state.sh
```

Then uncomment and update the backend block in `versions.tf` with your account ID.

### 2. Configure

```bash
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars — at minimum set alert_email
```

### 3. Deploy

```bash
terraform init
terraform plan -out=tfplan
terraform apply tfplan
```

### 4. Add Your Secrets

```bash
./scripts/update-secrets.sh
```

### 5. Connect

```bash
# Via SSM (immediate)
aws ssm start-session --target $(terraform output -raw instance_id)

# Via Tailscale (after instance joins your tailnet)
# http://<tailscale-ip>:18789
```

## Modules

| Module | Resources |
|---|---|
| **networking** | VPC, subnet, IGW, security groups, S3 endpoint |
| **security** | Secrets Manager, IAM roles/policies, CloudTrail (optional) |
| **storage** | EBS volume (encrypted, gp3), AWS Backup (daily + weekly) |
| **compute** | Launch template, ASG (self-healing), user data bootstrap |
| **monitoring** | CloudWatch logs/alarms/dashboard, SNS alerts, budget alerts |

## Configuration

| Variable | Default | Description |
|---|---|---|
| `region` | `eu-west-2` | AWS region |
| `instance_type` | `t3.micro` | EC2 instance type |
| `ebs_volume_size` | `15` | Data volume in GB |
| `alert_email` | — | **Required.** Email for alerts |
| `enable_cloudtrail` | `false` | Audit logging (~$2/month) |
| `backup_retention_days` | `3` | Daily backup retention |
| `backup_retention_weeks` | `14` | Weekly backup retention (days) |

## Cost Estimate

| Component | Monthly |
|---|---|
| EC2 (t3.micro) | ~$8 |
| EBS (15GB gp3) | ~$1.20 |
| EBS Snapshots | ~$0.75 |
| CloudWatch | ~$2.50 |
| Secrets Manager | ~$0.40 |
| AWS Backup | ~$0.75 |
| Data Transfer | ~$0.50 |
| **Total (t3.micro)** | **~$14** |
| **Total (t3.medium)** | **~$45** |

Costs vary by region. Reserved Instances reduce EC2 cost by ~35%.

## Security

- No public IP exposure — access via Tailscale VPN or SSM only
- Security groups deny all inbound by default
- IMDSv2 enforced (SSRF protection)
- Secrets in AWS Secrets Manager (encrypted at rest)
- EBS and backups encrypted with AWS-managed keys
- Dedicated IAM role with least-privilege policies
- Non-root user for OpenClaw process
- Optional CloudTrail for audit logging

## Operations

```bash
# Check infrastructure status
./scripts/quick-status.sh

# Update secrets
./scripts/update-secrets.sh

# View logs
aws logs tail /aws/ec2/openclaw/application --follow

# Scale up
# Edit terraform.tfvars: instance_type = "t3.medium"
terraform apply

# Destroy everything
terraform destroy
```

## Disaster Recovery

| Scenario | Recovery |
|---|---|
| Instance failure | ASG auto-replaces in ~10 min |
| Data loss | Restore from AWS Backup |
| Full infrastructure loss | `terraform apply` + restore backup |

## Contributing

Issues and PRs welcome. See the module structure above for where to make changes.

## License

Apache 2.0
