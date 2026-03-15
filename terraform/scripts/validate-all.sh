#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="$(dirname "$SCRIPT_DIR")"
ENVS_DIR="${TERRAFORM_DIR}/environments/production"

echo "=============================================="
echo "Validating All Regional Environments"
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

# Validate each region
for region_dir in "$ENVS_DIR"/*/; do
    region=$(basename "$region_dir")

    # Skip if not a directory or is empty
    [[ ! -d "$region_dir" ]] && continue
    [[ ! -f "${region_dir}main.tf" ]] && continue

    echo ""
    echo "=============================================="
    echo "Validating: $region"
    echo "=============================================="

    cd "$region_dir"

    # Initialize terraform (required for validation)
    echo "Initializing terraform..."
    if ! terraform init -input=false -backend=false; then
        echo "ERROR: terraform init failed for $region"
        RESULTS[$region]="INIT_FAILED"
        FAILED=1
        continue
    fi

    # Format check
    echo ""
    echo "Checking format..."
    if terraform fmt -check -recursive; then
        echo "Format: OK"
    else
        echo "WARNING: Format issues found. Run 'terraform fmt' to fix."
    fi

    # Validate
    echo ""
    echo "Running terraform validate..."
    if terraform validate; then
        RESULTS[$region]="VALID"
    else
        RESULTS[$region]="INVALID"
        FAILED=1
        echo "ERROR: terraform validate failed for $region"
    fi
done

# Summary
echo ""
echo "=============================================="
echo "Validation Summary"
echo "=============================================="
for region in "${!RESULTS[@]}"; do
    echo "  $region: ${RESULTS[$region]}"
done
echo ""

if [[ $FAILED -eq 0 ]]; then
    echo "All configurations are valid!"
else
    echo "Some validations failed. Please review the errors above."
    exit 1
fi
