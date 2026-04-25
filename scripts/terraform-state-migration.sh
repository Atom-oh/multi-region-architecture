#!/bin/bash
set -euo pipefail

# Terraform State Migration: Monolithic → Layered
# Splits us-east-1 and us-west-2 monolithic states into shared/eks/edge/dr layers.
#
# SAFETY:
# - Pulls states locally before any modification
# - Creates timestamped backups
# - Uses terraform state mv (no resources created/destroyed)
# - Validates each layer with terraform plan after migration
#
# USAGE:
#   ./scripts/terraform-state-migration.sh us-east-1   # Migrate us-east-1
#   ./scripts/terraform-state-migration.sh us-west-2   # Migrate us-west-2
#   ./scripts/terraform-state-migration.sh all          # Migrate both (us-east-1 first)

BUCKET="multi-region-mall-terraform-state"
LOCK_TABLE="multi-region-mall-terraform-locks"
STATE_REGION="us-east-1"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
ENV_DIR="$REPO_ROOT/terraform/environments/production"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log()   { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# ─────────────────────────────────────────────────────────────────────────────
# Pull state from S3 to local file
# ─────────────────────────────────────────────────────────────────────────────
pull_state() {
  local state_key="$1"
  local local_file="$2"
  log "Pulling state: s3://$BUCKET/$state_key → $local_file"
  aws s3 cp "s3://$BUCKET/$state_key" "$local_file" --region "$STATE_REGION"
}

# ─────────────────────────────────────────────────────────────────────────────
# Push local state file to S3
# ─────────────────────────────────────────────────────────────────────────────
push_state() {
  local local_file="$1"
  local state_key="$2"
  log "Pushing state: $local_file → s3://$BUCKET/$state_key"
  cd "$3"
  terraform init -reconfigure -input=false
  terraform state push "$local_file"
}

# ─────────────────────────────────────────────────────────────────────────────
# Move resources from one local state file to another
# ─────────────────────────────────────────────────────────────────────────────
move_resources() {
  local src="$1"
  local dst="$2"
  shift 2
  for resource in "$@"; do
    log "  Moving: $resource"
    terraform state mv -state="$src" -state-out="$dst" "$resource" "$resource" 2>/dev/null || {
      warn "  Skipped (not in state): $resource"
    }
  done
}

# ─────────────────────────────────────────────────────────────────────────────
# Migrate us-east-1
# ─────────────────────────────────────────────────────────────────────────────
migrate_us_east_1() {
  local region="us-east-1"
  local workdir="/tmp/tf-migration-$region-$TIMESTAMP"
  mkdir -p "$workdir"

  log "═══════════════════════════════════════════════════════"
  log "Migrating $region monolithic → layered"
  log "═══════════════════════════════════════════════════════"

  # Step 1: Pull and backup monolithic state
  local mono_state="$workdir/monolithic.tfstate"
  local backup="$workdir/monolithic-backup-$TIMESTAMP.tfstate"
  pull_state "production/$region/terraform.tfstate" "$mono_state"
  cp "$mono_state" "$backup"
  log "Backup saved: $backup"

  # Step 2: Create empty target states
  local shared_state="$workdir/shared.tfstate"
  local eks_state="$workdir/eks.tfstate"
  local edge_state="$workdir/edge.tfstate"
  local dr_state="$workdir/dr.tfstate"

  # Step 3: Move resources to shared layer
  log "── Moving resources to shared/ ──"
  move_resources "$mono_state" "$shared_state" \
    "module.vpc" \
    "module.transit_gateway" \
    "module.security_groups" \
    "module.kms" \
    "module.secrets_manager" \
    "module.iam" \
    "module.nlb" \
    "random_password.aurora" \
    "module.aurora" \
    "random_password.documentdb" \
    "module.dsql" \
    "module.documentdb" \
    "module.elasticache" \
    "module.msk" \
    "module.opensearch" \
    "module.s3"

  # Step 4: Move resources to eks layer
  log "── Moving resources to eks/ ──"
  move_resources "$mono_state" "$eks_state" \
    "module.eks" \
    "module.alb" \
    "module.dsql_irsa" \
    "module.tempo_storage" \
    "module.otel_collector_irsa" \
    "module.cloudwatch" \
    "module.xray"

  # Step 5: Move resources to edge layer
  log "── Moving resources to edge/ ──"
  move_resources "$mono_state" "$edge_state" \
    "module.waf" \
    "module.cloudfront" \
    "module.cloudfront_argocd" \
    "module.cloudfront_grafana" \
    "module.route53" \
    "module.cognito" \
    "aws_kms_key_policy.s3_cloudfront" \
    "aws_route53_record.argocd" \
    'aws_route53_record.argocd_internal[0]' \
    "aws_route53_record.grafana" \
    'aws_route53_record.grafana_internal[0]'

  # Step 6: Move resources to dr layer
  log "── Moving resources to dr/ ──"
  move_resources "$mono_state" "$dr_state" \
    "module.dr_automation"

  # Step 7: Check remaining resources in monolithic state
  log "── Checking remaining resources in monolithic state ──"
  local remaining
  remaining=$(terraform state list -state="$mono_state" 2>/dev/null | grep -v "^$" || true)
  if [ -n "$remaining" ]; then
    warn "Resources still in monolithic state (not migrated):"
    echo "$remaining"
  else
    log "All resources migrated successfully!"
  fi

  # Step 8: Push layered states to S3
  log "── Pushing layered states to S3 ──"
  if [ -f "$shared_state" ]; then
    push_state "$shared_state" "production/$region/shared/terraform.tfstate" "$ENV_DIR/$region/shared"
  fi
  if [ -f "$eks_state" ]; then
    push_state "$eks_state" "production/$region/eks/terraform.tfstate" "$ENV_DIR/$region/eks"
  fi
  if [ -f "$edge_state" ]; then
    push_state "$edge_state" "production/$region/edge/terraform.tfstate" "$ENV_DIR/$region/edge"
  fi
  if [ -f "$dr_state" ]; then
    push_state "$dr_state" "production/$region/dr/terraform.tfstate" "$ENV_DIR/$region/dr"
  fi

  # Step 9: Verify with terraform plan
  log "── Verifying with terraform plan ──"
  for layer in shared eks edge dr; do
    log "  Plan: $region/$layer"
    cd "$ENV_DIR/$region/$layer"
    terraform init -reconfigure -input=false > /dev/null 2>&1
    local plan_output
    plan_output=$(terraform plan -detailed-exitcode 2>&1) && plan_exit=$? || plan_exit=$?
    if [ $plan_exit -eq 0 ]; then
      echo -e "  ${GREEN}✓ No changes${NC}"
    elif [ $plan_exit -eq 2 ]; then
      echo -e "  ${YELLOW}⚠ Changes detected:${NC}"
      echo "$plan_output" | grep -E "^(  #|Plan:)" | head -20
    else
      echo -e "  ${RED}✗ Error${NC}"
      echo "$plan_output" | tail -20
    fi
  done

  log "us-east-1 migration complete. Backup at: $backup"
}

# ─────────────────────────────────────────────────────────────────────────────
# Migrate us-west-2
# ─────────────────────────────────────────────────────────────────────────────
migrate_us_west_2() {
  local region="us-west-2"
  local workdir="/tmp/tf-migration-$region-$TIMESTAMP"
  mkdir -p "$workdir"

  log "═══════════════════════════════════════════════════════"
  log "Migrating $region monolithic → layered"
  log "═══════════════════════════════════════════════════════"

  # Step 1: Pull and backup
  local mono_state="$workdir/monolithic.tfstate"
  local backup="$workdir/monolithic-backup-$TIMESTAMP.tfstate"
  pull_state "production/$region/terraform.tfstate" "$mono_state"
  cp "$mono_state" "$backup"
  log "Backup saved: $backup"

  # Step 2: Create target states
  local shared_state="$workdir/shared.tfstate"
  local eks_state="$workdir/eks.tfstate"
  local edge_state="$workdir/edge.tfstate"

  # Step 3: Move to shared
  log "── Moving resources to shared/ ──"
  move_resources "$mono_state" "$shared_state" \
    "data.terraform_remote_state.primary" \
    "module.vpc" \
    "module.transit_gateway" \
    "module.security_groups" \
    "module.kms" \
    "module.secrets_manager" \
    "module.iam" \
    "module.nlb" \
    "module.aurora" \
    "module.dsql" \
    "module.documentdb" \
    "module.elasticache" \
    "module.msk" \
    "module.opensearch" \
    "module.s3"

  # Step 4: Move to eks
  log "── Moving resources to eks/ ──"
  move_resources "$mono_state" "$eks_state" \
    "module.eks" \
    "module.alb" \
    "module.dsql_irsa" \
    "module.tempo_storage" \
    "module.otel_collector_irsa" \
    "module.cloudwatch" \
    "module.xray"

  # Step 5: Move to edge
  log "── Moving resources to edge/ ──"
  move_resources "$mono_state" "$edge_state" \
    "module.route53"

  # Step 6: Check remaining
  log "── Checking remaining resources ──"
  local remaining
  remaining=$(terraform state list -state="$mono_state" 2>/dev/null | grep -v "^$" || true)
  if [ -n "$remaining" ]; then
    warn "Resources still in monolithic state:"
    echo "$remaining"
  else
    log "All resources migrated!"
  fi

  # Step 7: Push to S3
  log "── Pushing layered states to S3 ──"
  if [ -f "$shared_state" ]; then
    push_state "$shared_state" "production/$region/shared/terraform.tfstate" "$ENV_DIR/$region/shared"
  fi
  if [ -f "$eks_state" ]; then
    push_state "$eks_state" "production/$region/eks/terraform.tfstate" "$ENV_DIR/$region/eks"
  fi
  if [ -f "$edge_state" ]; then
    push_state "$edge_state" "production/$region/edge/terraform.tfstate" "$ENV_DIR/$region/edge"
  fi

  # Step 8: Verify
  log "── Verifying with terraform plan ──"
  for layer in shared eks edge; do
    log "  Plan: $region/$layer"
    cd "$ENV_DIR/$region/$layer"
    terraform init -reconfigure -input=false > /dev/null 2>&1
    local plan_output
    plan_output=$(terraform plan -detailed-exitcode 2>&1) && plan_exit=$? || plan_exit=$?
    if [ $plan_exit -eq 0 ]; then
      echo -e "  ${GREEN}✓ No changes${NC}"
    elif [ $plan_exit -eq 2 ]; then
      echo -e "  ${YELLOW}⚠ Changes detected:${NC}"
      echo "$plan_output" | grep -E "^(  #|Plan:)" | head -20
    else
      echo -e "  ${RED}✗ Error${NC}"
      echo "$plan_output" | tail -20
    fi
  done

  log "us-west-2 migration complete. Backup at: $backup"
}

# ─────────────────────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────────────────────
case "${1:-}" in
  us-east-1)
    migrate_us_east_1
    ;;
  us-west-2)
    migrate_us_west_2
    ;;
  all)
    migrate_us_east_1
    echo ""
    migrate_us_west_2
    ;;
  *)
    echo "Usage: $0 {us-east-1|us-west-2|all}"
    echo ""
    echo "Migrates monolithic Terraform state to layered structure."
    echo "us-east-1 MUST be migrated before us-west-2 (cross-region dependency)."
    exit 1
    ;;
esac
