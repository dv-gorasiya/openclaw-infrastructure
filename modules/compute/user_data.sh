#!/bin/bash
set -euo pipefail

exec > >(tee /var/log/openclaw-setup.log)
exec 2>&1

log() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"; }
error_exit() { log "ERROR: $1"; exit 1; }

log "========= OpenClaw Setup Started ========="

# Create 1GB swap to prevent OOM during npm install on small instances
log "[0/12] Creating swap file..."
if [ ! -f /swapfile ]; then
    dd if=/dev/zero of=/swapfile bs=1M count=1024 status=none
    chmod 600 /swapfile
    mkswap /swapfile >/dev/null
    swapon /swapfile
    echo '/swapfile none swap sw 0 0' >> /etc/fstab
    log "Swap enabled: $(swapon --show --noheadings)"
fi

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
TOKEN=$(curl -sX PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 300")
INSTANCE_ID=$(curl -sH "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/instance-id)

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

# Restart CW Agent now that mount exists — rewrite config since fetch-config
# moves the original file into the .d/ directory on first run
cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json <<'CWCONFIG2'
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
CWCONFIG2
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
    -a fetch-config -m ec2 \
    -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json -s || \
    log "WARNING: CloudWatch Agent restart failed"

# 8. Create runtime secrets loader (fetches from Secrets Manager into tmpfs)
log "[8/12] Configuring runtime secrets loader..."
cat > /usr/local/bin/openclaw-load-secrets <<LOADEREOF
#!/bin/bash
set -euo pipefail
mkdir -p /run/openclaw
SECRETS=\$(/usr/local/bin/aws secretsmanager get-secret-value \\
    --region "$REGION" --secret-id "$SECRETS_MANAGER_NAME" \\
    --query SecretString --output text)

ANTHROPIC_KEY=\$(echo "\$SECRETS" | jq -r '.ANTHROPIC_API_KEY // ""')
GATEWAY_TOKEN=\$(echo "\$SECRETS" | jq -r '.OPENCLAW_GATEWAY_TOKEN // ""')

{
  printf 'ANTHROPIC_API_KEY=%q\n' "\$ANTHROPIC_KEY"
  printf 'OPENCLAW_GATEWAY_TOKEN=%q\n' "\$GATEWAY_TOKEN"
  echo 'GATEWAY_PORT=$OPENCLAW_GATEWAY_PORT'
  echo 'BROWSER_CONTROL_PORT=$OPENCLAW_BROWSER_PORT'
  echo 'DATA_DIR=/mnt/openclaw-data'
} > /run/openclaw/.env

chown openclaw:openclaw /run/openclaw/.env
chmod 600 /run/openclaw/.env
LOADEREOF
chmod 755 /usr/local/bin/openclaw-load-secrets

# 9. Verify secrets access works
log "[9/12] Verifying Secrets Manager access..."
/usr/local/bin/openclaw-load-secrets || error_exit "Failed to load secrets"
log "Secrets loaded to /run/openclaw/.env (tmpfs — never written to disk)"

# Fetch Tailscale key for step 12 (only needed during setup)
TAILSCALE_AUTH_KEY=$(/usr/local/bin/aws secretsmanager get-secret-value \
    --region "$REGION" --secret-id "$SECRETS_MANAGER_NAME" \
    --query SecretString --output text | jq -r '.TAILSCALE_AUTH_KEY // ""')

# 10. Install OpenClaw via npm (official method)
log "[10/12] Installing OpenClaw..."
export HOME=/root
npm install -g openclaw@latest 2>&1 || error_exit "Failed to install OpenClaw via npm"

OPENCLAW_BIN=$(which openclaw 2>/dev/null || echo "")
if [ -n "$OPENCLAW_BIN" ]; then
    log "OpenClaw installed at $OPENCLAW_BIN: $(openclaw --version 2>/dev/null || echo 'unknown')"
else
    error_exit "openclaw binary not found in PATH after npm install"
fi

# 11. Systemd service
log "[11/12] Configuring systemd service..."
cat > /etc/systemd/system/openclaw.service <<SVCEOF
[Unit]
Description=OpenClaw AI Assistant Gateway
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=openclaw
Group=openclaw
WorkingDirectory=/mnt/openclaw-data
RuntimeDirectory=openclaw
ExecStartPre=+/usr/local/bin/openclaw-load-secrets
ExecStart=/bin/bash -c 'set -a; source /run/openclaw/.env; exec openclaw gateway --port \$GATEWAY_PORT'
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
