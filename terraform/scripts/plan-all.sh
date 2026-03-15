#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="$(dirname "$SCRIPT_DIR")"
ENVS_DIR="${TERRAFORM_DIR}/environments/production"

echo "=============================================="
echo "Planning All Regional Environments"
echo "=============================================="

# Check if terraform is installed
if ! command -v terraform &> /dev/null; then
    echo "ERROR: terraform is not installed or not in PATH"
    exit 1
fi

# Check if environments directory exists
if [[ ! -d "$ENVS_DIR" ]]; then
    echo "ERROR: Environments directory not found: $ENVS_DIR"
    exit 1
fi

# Track results
declare -A RESULTS
FAILED=0

# Plan each region
for region_dir in "$ENVS_DIR"/*/; do
    region=$(basename "$region_dir")

    # Skip if not a directory or is empty
    [[ ! -d "$region_dir" ]] && continue
    [[ ! -f "${region_dir}main.tf" ]] && continue

    echo ""
    echo "=============================================="
    echo "Planning: $region"
    echo "=============================================="

    cd "$region_dir"

    # Initialize terraform
    echo "Initializing terraform..."
    if ! terraform init -input=false -upgrade; then
        echo "ERROR: terraform init failed for $region"
        RESULTS[$region]="INIT_FAILED"
        FAILED=1
        continue
    fi

    # Create plan
    echo ""
    echo "Creating plan..."
    if terraform plan -out="tfplan-${region}" -input=false; then
        RESULTS[$region]="SUCCESS"
        echo ""
        echo "Plan saved to: tfplan-${region}"
    else
        RESULTS[$region]="PLAN_FAILED"
        FAILED=1
        echo "ERROR: terraform plan failed for $region"
    fi
done

# Summary
echo ""
echo "=============================================="
echo "Planning Summary"
echo "=============================================="
for region in "${!RESULTS[@]}"; do
    echo "  $region: ${RESULTS[$region]}"
done
echo ""

if [[ $FAILED -eq 0 ]]; then
    echo "All plans generated successfully!"
    echo ""
    echo "To apply, run: ./apply-all.sh"
    echo "Or apply individually with: cd environments/production/<region> && terraform apply tfplan-<region>"
else
    echo "Some plans failed. Please review the errors above."
    exit 1
fi
