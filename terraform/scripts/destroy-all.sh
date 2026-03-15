#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="$(dirname "$SCRIPT_DIR")"
ENVS_DIR="${TERRAFORM_DIR}/environments/production"

echo "=============================================="
echo "WARNING: Destroying All Regional Environments"
echo "=============================================="
echo ""
echo "This will destroy all infrastructure in:"
echo "  - us-west-2 (secondary)"
echo "  - us-east-1 (primary)"
echo ""

# Confirmation prompt
read -p "Are you sure you want to destroy ALL infrastructure? (type 'yes' to confirm): " CONFIRM
if [[ "$CONFIRM" != "yes" ]]; then
    echo "Aborted."
    exit 0
fi

# Check if terraform is installed
if ! command -v terraform &> /dev/null; then
    echo "ERROR: terraform is not installed or not in PATH"
    exit 1
fi

# Define the order of regions (secondary first, then primary)
# This is the reverse of apply order for proper dependency handling
REGIONS=("us-west-2" "us-east-1")

# Track results
declare -A RESULTS
FAILED=0

# Destroy each region in order
for region in "${REGIONS[@]}"; do
    region_dir="${ENVS_DIR}/${region}"

    # Skip if directory doesn't exist
    if [[ ! -d "$region_dir" ]]; then
        echo "WARNING: Region directory not found: $region_dir"
        continue
    fi

    # Skip if no main.tf
    if [[ ! -f "${region_dir}/main.tf" ]]; then
        echo "WARNING: No main.tf found in $region_dir"
        continue
    fi

    echo ""
    echo "=============================================="
    echo "Destroying: $region"
    echo "=============================================="

    cd "$region_dir"

    # Initialize terraform
    echo "Initializing terraform..."
    if ! terraform init -input=false; then
        echo "ERROR: terraform init failed for $region"
        RESULTS[$region]="INIT_FAILED"
        FAILED=1
        continue
    fi

    # Destroy
    echo "Running terraform destroy..."
    if terraform destroy -auto-approve -input=false; then
        RESULTS[$region]="DESTROYED"
    else
        RESULTS[$region]="DESTROY_FAILED"
        FAILED=1
        echo "ERROR: terraform destroy failed for $region"
    fi

    echo ""
    echo "=== $region complete ==="
done

# Summary
echo ""
echo "=============================================="
echo "Destroy Summary"
echo "=============================================="
for region in "${REGIONS[@]}"; do
    status="${RESULTS[$region]:-NOT_STARTED}"
    echo "  $region: $status"
done
echo ""

if [[ $FAILED -eq 0 ]]; then
    echo "All regions destroyed successfully!"
else
    echo "Some destroy operations failed. Please review the errors above."
    exit 1
fi
