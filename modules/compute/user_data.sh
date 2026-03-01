#!/bin/bash
set -euo pipefail

exec > >(tee /var/log/openclaw-setup.log)
exec 2>&1

log() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"; }
error_exit() { log "ERROR: $1"; exit 1; }

log "========= OpenClaw Setup Started ========="

REGION="${region}"
SECRETS_MANAGER_NAME="${secrets_manager_name}"
EBS_VOLUME_ID="${ebs_volume_id}"
OPENCLAW_GATEWAY_PORT="${gateway_port}"
OPENCLAW_BROWSER_PORT="${browser_port}"

# 1. System packages
log "[1/12] Updating system packages..."
export DEBIAN_FRONTEND=noninteractive
apt-get update || error_exit "Failed to update package list"
apt-get upgrade -y || log "WARNING: Some packages failed to upgrade"

# 2. Dependencies
log "[2/12] Installing dependencies..."
apt-get install -y \
    curl wget git jq unzip build-essential \
    ca-certificates gnupg lsb-release || error_exit "Failed to install dependencies"

# 3. Node.js 22
log "[3/12] Installing Node.js 22..."
curl -fsSL https://deb.nodesource.com/setup_22.x | bash - || error_exit "Failed to add Node.js repo"
apt-get install -y nodejs || error_exit "Failed to install Node.js"
log "Node.js $(node --version)"

# 4. AWS CLI v2
log "[4/12] Installing AWS CLI v2..."
cd /tmp
curl -s "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip -qo awscliv2.zip
./aws/install --update || error_exit "Failed to install AWS CLI"
log "AWS CLI $(/usr/local/bin/aws --version)"

# 5. CloudWatch Agent (for memory/disk metrics)
log "[5/12] Installing CloudWatch Agent..."
cd /tmp
curl -sO https://s3.amazonaws.com/amazoncloudwatch-agent/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb
dpkg -i amazon-cloudwatch-agent.deb || apt-get -f install -y

cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json <<'CWCONFIG'
{
  "agent": { "metrics_collection_interval": 300, "run_as_user": "root" },
  "metrics": {
    "namespace": "OpenClaw",
    "append_dimensions": { "InstanceId": "$${aws:InstanceId}" },
    "metrics_collected": {
      "mem": { "measurement": ["mem_used_percent"], "metrics_collection_interval": 300 },
      "disk": {
        "measurement": ["used_percent"],
        "metrics_collection_interval": 300,
        "resources": ["/mnt/openclaw-data", "/"]
      }
    }
  }
}
CWCONFIG

/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
    -a fetch-config -m ec2 \
    -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json -s || \
    log "WARNING: CloudWatch Agent config failed, will retry after mount"

# 6. Create user
log "[6/12] Creating openclaw user..."
id openclaw &>/dev/null || useradd -r -m -s /bin/bash openclaw

# 7. Attach and mount EBS volume
log "[7/12] Mounting EBS volume..."
INSTANCE_ID=$(ec2-metadata --instance-id | cut -d " " -f 2)

for i in {1..30}; do
    VOLUME_STATE=$(/usr/local/bin/aws ec2 describe-volumes \
        --region "$REGION" --volume-ids "$EBS_VOLUME_ID" \
        --query 'Volumes[0].State' --output text)
    if [ "$VOLUME_STATE" == "available" ]; then
        /usr/local/bin/aws ec2 attach-volume \
            --region "$REGION" --volume-id "$EBS_VOLUME_ID" \
            --instance-id "$INSTANCE_ID" --device /dev/xvdf || \
            log "WARNING: Attach failed (may already be attached)"
        break
    fi
    log "Waiting for volume... ($i/30)"
    sleep 10
done

DEVICE=""
for i in {1..30}; do
    if [ -b /dev/xvdf ]; then DEVICE="/dev/xvdf"; break; fi
    if [ -b /dev/nvme1n1 ]; then DEVICE="/dev/nvme1n1"; break; fi
    log "Waiting for device... ($i/30)"
    sleep 2
done
[ -z "$DEVICE" ] && error_exit "EBS device not found after 60s"

blkid "$DEVICE" | grep -q ext4 || mkfs.ext4 "$DEVICE"

mkdir -p /mnt/openclaw-data
mount | grep -q /mnt/openclaw-data || mount "$DEVICE" /mnt/openclaw-data

VOLUME_UUID=$(blkid -s UUID -o value "$DEVICE")
grep -q "$VOLUME_UUID" /etc/fstab || \
    echo "UUID=$VOLUME_UUID /mnt/openclaw-data ext4 defaults,nofail 0 2" >> /etc/fstab

chown -R openclaw:openclaw /mnt/openclaw-data
chmod 755 /mnt/openclaw-data
log "EBS mounted at /mnt/openclaw-data"

# Restart CW Agent now that mount exists
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
    -a fetch-config -m ec2 \
    -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json -s || \
    log "WARNING: CloudWatch Agent restart failed"

# 8. Fetch secrets
log "[8/12] Fetching secrets..."
SECRETS_JSON=$(/usr/local/bin/aws secretsmanager get-secret-value \
    --region "$REGION" --secret-id "$SECRETS_MANAGER_NAME" \
    --query SecretString --output text) || error_exit "Failed to fetch secrets"

ANTHROPIC_API_KEY=$(echo "$SECRETS_JSON" | jq -r '.ANTHROPIC_API_KEY // ""')
OPENCLAW_GATEWAY_TOKEN=$(echo "$SECRETS_JSON" | jq -r '.OPENCLAW_GATEWAY_TOKEN // ""')
TAILSCALE_AUTH_KEY=$(echo "$SECRETS_JSON" | jq -r '.TAILSCALE_AUTH_KEY // ""')

# 9. Environment config
log "[9/12] Writing environment config..."
cat > /mnt/openclaw-data/.env <<EOF
ANTHROPIC_API_KEY=$ANTHROPIC_API_KEY
OPENCLAW_GATEWAY_TOKEN=$OPENCLAW_GATEWAY_TOKEN
GATEWAY_PORT=$OPENCLAW_GATEWAY_PORT
BROWSER_CONTROL_PORT=$OPENCLAW_BROWSER_PORT
DATA_DIR=/mnt/openclaw-data
EOF

chown openclaw:openclaw /mnt/openclaw-data/.env
chmod 600 /mnt/openclaw-data/.env

# 10. Install OpenClaw
log "[10/12] Installing OpenClaw..."
export HOME=/root
curl -fsSL https://openclaw.ai/install.sh | bash || log "WARNING: OpenClaw install had issues"

if command -v openclaw &>/dev/null; then
    log "OpenClaw installed: $(openclaw --version 2>/dev/null || echo 'unknown')"
else
    log "WARNING: openclaw not in PATH"
fi

# 11. Systemd service
log "[11/12] Configuring systemd service..."
cat > /etc/systemd/system/openclaw.service <<'SVCEOF'
[Unit]
Description=OpenClaw AI Assistant Gateway
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=openclaw
Group=openclaw
WorkingDirectory=/mnt/openclaw-data
EnvironmentFile=/mnt/openclaw-data/.env
ExecStart=/bin/bash -c 'openclaw start || echo "OpenClaw not found"'
Restart=always
RestartSec=10s
StandardOutput=journal
StandardError=journal
SyslogIdentifier=openclaw

[Install]
WantedBy=multi-user.target
SVCEOF

systemctl daemon-reload
systemctl enable openclaw.service

# 12. Tailscale
log "[12/12] Setting up Tailscale..."
if [ -n "$TAILSCALE_AUTH_KEY" ] && [ "$TAILSCALE_AUTH_KEY" != "null" ] && [ "$TAILSCALE_AUTH_KEY" != "" ]; then
    curl -fsSL https://tailscale.com/install.sh | sh || log "WARNING: Tailscale install failed"
    tailscale up --authkey="$TAILSCALE_AUTH_KEY" --hostname=openclaw-gateway --accept-routes || \
        log "WARNING: Tailscale connection failed"
    log "Tailscale IP: $(tailscale ip -4 2>/dev/null || echo 'pending')"
else
    log "No Tailscale auth key, skipping"
fi

# Start service
systemctl start openclaw.service || log "WARNING: Service failed to start"
sleep 5

# Status script
cat > /usr/local/bin/openclaw-status <<'STATUSEOF'
#!/bin/bash
echo "=== OpenClaw Status ==="
systemctl status openclaw.service --no-pager 2>/dev/null || echo "Service not found"
echo ""; echo "Disk:"; df -h /mnt/openclaw-data
echo ""; echo "Memory:"; free -h
command -v tailscale &>/dev/null && { echo ""; echo "Tailscale:"; tailscale status; }
echo ""; echo "Recent logs:"
journalctl -u openclaw.service -n 20 --no-pager 2>/dev/null
STATUSEOF
chmod +x /usr/local/bin/openclaw-status

log "========= OpenClaw Setup Completed ========="
echo "$(date)" > /var/log/openclaw-setup-complete
