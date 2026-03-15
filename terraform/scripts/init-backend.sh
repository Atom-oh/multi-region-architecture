#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="$(dirname "$SCRIPT_DIR")"

echo "=============================================="
echo "Initializing Terraform Backend Infrastructure"
echo "=============================================="

# Check if terraform is installed
if ! command -v terraform &> /dev/null; then
    echo "ERROR: terraform is not installed or not in PATH"
    exit 1
fi

# Navigate to the terraform-state module
BACKEND_DIR="${TERRAFORM_DIR}/global/terraform-state"

if [[ ! -d "$BACKEND_DIR" ]]; then
    echo "ERROR: Backend directory not found: $BACKEND_DIR"
    exit 1
fi

cd "$BACKEND_DIR"

echo "Working directory: $(pwd)"
echo ""

# Initialize Terraform
echo "Running terraform init..."
terraform init

# Plan first to show what will be created
echo ""
echo "Running terraform plan..."
terraform plan -out=tfplan

# Apply the changes
echo ""
echo "Running terraform apply..."
terraform apply tfplan

# Cleanup plan file
rm -f tfplan

echo ""
echo "=============================================="
echo "Backend infrastructure created successfully!"
echo "=============================================="
echo ""
echo "S3 Bucket: multi-region-mall-terraform-state"
echo "DynamoDB Table: multi-region-mall-terraform-locks"
echo ""
echo "You can now initialize the regional environments."
