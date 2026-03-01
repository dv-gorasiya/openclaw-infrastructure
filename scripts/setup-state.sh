#!/bin/bash
set -e

echo "========================================="
echo "OpenClaw — Terraform State Setup"
echo "========================================="

command -v aws &>/dev/null || { echo "Error: AWS CLI not installed"; exit 1; }
aws sts get-caller-identity &>/dev/null || { echo "Error: AWS credentials not configured"; exit 1; }

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGION="${AWS_REGION:-eu-west-2}"
BUCKET="openclaw-tf-state-$ACCOUNT_ID"
TABLE="openclaw-terraform-locks"

echo "Account: $ACCOUNT_ID"
echo "Region:  $REGION"
echo "Bucket:  $BUCKET"
echo "Table:   $TABLE"
echo ""

echo "[1/4] Creating S3 bucket..."
aws s3 mb "s3://$BUCKET" --region "$REGION" 2>/dev/null && echo "Done" || echo "Already exists"

echo "[2/4] Enabling versioning..."
aws s3api put-bucket-versioning --bucket "$BUCKET" \
    --versioning-configuration Status=Enabled --region "$REGION"

echo "[3/4] Enabling encryption..."
aws s3api put-bucket-encryption --bucket "$BUCKET" --region "$REGION" \
    --server-side-encryption-configuration '{
        "Rules": [{"ApplyServerSideEncryptionByDefault": {"SSEAlgorithm": "AES256"}, "BucketKeyEnabled": false}]
    }'

echo "[4/4] Creating DynamoDB table..."
aws dynamodb create-table --table-name "$TABLE" \
    --attribute-definitions AttributeName=LockID,AttributeType=S \
    --key-schema AttributeName=LockID,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST \
    --region "$REGION" 2>/dev/null && {
    echo "Waiting for table..."
    aws dynamodb wait table-exists --table-name "$TABLE" --region "$REGION"
    echo "Done"
} || echo "Already exists"

echo ""
echo "Now update versions.tf backend block:"
echo ""
echo "  backend \"s3\" {"
echo "    bucket         = \"$BUCKET\""
echo "    key            = \"openclaw/terraform.tfstate\""
echo "    region         = \"$REGION\""
echo "    encrypt        = true"
echo "    dynamodb_table = \"$TABLE\""
echo "  }"
echo ""
echo "Then run: terraform init"
