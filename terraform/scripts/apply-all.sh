#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="$(dirname "$SCRIPT_DIR")"
ENVS_DIR="${TERRAFORM_DIR}/environments/production"

echo "=============================================="
echo "Applying All Regional Environments"
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

# Define the order of regions (primary first, then secondary)
# This is important for cross-region dependencies
REGIONS=("us-east-1" "us-west-2")

# Track results
declare -A RESULTS
FAILED=0

# Apply each region in order
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
    echo "Applying: $region"
    echo "=============================================="

    cd "$region_dir"

    # Initialize terraform
    echo "Initializing terraform..."
    if ! terraform init -input=false -upgrade; then
        echo "ERROR: terraform init failed for $region"
        RESULTS[$region]="INIT_FAILED"
        FAILED=1
        echo ""
        echo "Stopping deployment due to failure in $region"
        break
    fi

    # Check if a plan file exists
    PLAN_FILE="tfplan-${region}"
    if [[ -f "$PLAN_FILE" ]]; then
        echo "Using existing plan file: $PLAN_FILE"
        if terraform apply -input=false "$PLAN_FILE"; then
            RESULTS[$region]="SUCCESS"
            rm -f "$PLAN_FILE"
        else
            RESULTS[$region]="APPLY_FAILED"
            FAILED=1
            echo "ERROR: terraform apply failed for $region"
            echo ""
            echo "Stopping deployment due to failure in $region"
            break
        fi
    else
        # No plan file, run plan and apply
        echo "No plan file found, running plan and apply..."
        if terraform apply -auto-approve -input=false; then
            RESULTS[$region]="SUCCESS"
        else
            RESULTS[$region]="APPLY_FAILED"
            FAILED=1
            echo "ERROR: terraform apply failed for $region"
            echo ""
            echo "Stopping deployment due to failure in $region"
            break
        fi
    fi

    echo ""
    echo "=== $region complete ==="
done

# Summary
echo ""
echo "=============================================="
echo "Deployment Summary"
echo "=============================================="
for region in "${REGIONS[@]}"; do
    status="${RESULTS[$region]:-NOT_STARTED}"
    echo "  $region: $status"
done
echo ""

if [[ $FAILED -eq 0 ]]; then
    echo "All regions applied successfully!"
else
    echo "Deployment failed. Please review the errors above."
    echo ""
    echo "Note: Regions are applied in order (us-east-1 first, then us-west-2)"
    echo "      because us-west-2 depends on outputs from us-east-1."
    exit 1
fi
