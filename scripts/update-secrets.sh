#!/bin/bash
set -e

echo "========================================="
echo "OpenClaw — Update Secrets"
echo "========================================="

command -v terraform &>/dev/null || { echo "Error: Terraform not installed"; exit 1; }

SECRET_NAME=$(terraform output -raw secrets_manager_name 2>/dev/null)
GATEWAY_TOKEN=$(terraform output -raw gateway_token 2>/dev/null)
[ -z "$SECRET_NAME" ] && { echo "Error: Run terraform apply first"; exit 1; }

echo "Secret: $SECRET_NAME"
echo ""
echo "Enter values (blank = keep existing):"
echo ""

read -rp "Anthropic API Key: " ANTHROPIC_KEY
read -rp "Tailscale Auth Key: " TAILSCALE_KEY

EXISTING=$(aws secretsmanager get-secret-value \
    --secret-id "$SECRET_NAME" --query SecretString --output text 2>/dev/null || echo '{}')

FINAL_ANTHROPIC=${ANTHROPIC_KEY:-$(echo "$EXISTING" | jq -r '.ANTHROPIC_API_KEY // ""')}
FINAL_TAILSCALE=${TAILSCALE_KEY:-$(echo "$EXISTING" | jq -r '.TAILSCALE_AUTH_KEY // ""')}

SECRET_JSON=$(jq -n \
    --arg anthropic "$FINAL_ANTHROPIC" \
    --arg gateway "$GATEWAY_TOKEN" \
    --arg tailscale "$FINAL_TAILSCALE" \
    '{ ANTHROPIC_API_KEY: $anthropic, OPENCLAW_GATEWAY_TOKEN: $gateway, TAILSCALE_AUTH_KEY: $tailscale }')

aws secretsmanager put-secret-value --secret-id "$SECRET_NAME" --secret-string "$SECRET_JSON"
echo "Secrets updated."

INSTANCE_ID=$(terraform output -raw instance_id 2>/dev/null)
if [ -n "$INSTANCE_ID" ]; then
    read -rp "Reboot instance to reload? (y/n): " REBOOT
    if [ "$REBOOT" = "y" ]; then
        aws ec2 reboot-instances --instance-ids "$INSTANCE_ID"
        echo "Rebooting $INSTANCE_ID — wait 5-10 minutes."
    fi
fi
