#!/bin/bash

echo "========================================="
echo "OpenClaw — Infrastructure Status"
echo "========================================="

command -v terraform &>/dev/null || { echo "Error: Terraform not installed"; exit 1; }

INSTANCE_ID=$(terraform output -raw instance_id 2>/dev/null)
ASG_NAME=$(terraform output -raw asg_name 2>/dev/null)

if [ -n "$INSTANCE_ID" ]; then
    STATE=$(aws ec2 describe-instances --instance-ids "$INSTANCE_ID" \
        --query 'Reservations[0].Instances[0].State.Name' --output text 2>/dev/null)
    echo "Instance: $INSTANCE_ID ($STATE)"
fi

if [ -n "$ASG_NAME" ]; then
    ASG_INFO=$(aws autoscaling describe-auto-scaling-groups \
        --auto-scaling-group-names "$ASG_NAME" \
        --query 'AutoScalingGroups[0].[DesiredCapacity,Instances[0].HealthStatus]' \
        --output text 2>/dev/null)
    echo "ASG: $ASG_NAME ($ASG_INFO)"
fi

echo ""
echo "Alarms:"
aws cloudwatch describe-alarms --alarm-name-prefix "openclaw-" \
    --query 'MetricAlarms[*].[AlarmName,StateValue]' --output text 2>/dev/null | \
    while read -r name state; do
        [ "$state" = "OK" ] && echo "  OK    $name" || echo "  WARN  $name ($state)"
    done

echo ""
echo "Connect: aws ssm start-session --target $INSTANCE_ID"
DASHBOARD=$(terraform output -raw dashboard_url 2>/dev/null)
[ -n "$DASHBOARD" ] && echo "Dashboard: $DASHBOARD"
