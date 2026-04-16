#!/bin/bash
# ============================================================================
# Multi-Region Shopping Mall - Master Seed Script
# Orchestrates seeding across all data stores
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REGION="${AWS_REGION:-us-east-1}"

echo "============================================"
echo " Shopping Mall - Data Seeding"
echo " Region: ${REGION}"
echo " Time:   $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "============================================"
echo ""

FAILED=0
SUCCEEDED=0

run_step() {
  local name=$1
  local cmd=$2
  echo "──────────────────────────────────────────"
  echo "▶ ${name}"
  echo "──────────────────────────────────────────"
  if eval "$cmd"; then
    echo "✓ ${name} completed"
    SUCCEEDED=$((SUCCEEDED + 1))
  else
    echo "✗ ${name} FAILED (continuing...)"
    FAILED=$((FAILED + 1))
  fi
  echo ""
}

# ── Step 1: Aurora PostgreSQL / DSQL ───────────────────────────────────────
if [ -n "${AURORA_ENDPOINT:-}" ]; then
  # Detect Aurora DSQL endpoint and use IAM auth
  if [[ "${AURORA_ENDPOINT}" == *".dsql."* ]]; then
    echo "  ℹ Detected Aurora DSQL endpoint, generating IAM auth token..."
    AURORA_PASSWORD=$(aws dsql generate-db-connect-admin-auth-token \
      --hostname "${AURORA_ENDPOINT}" --region "${REGION}" 2>&1) || {
      echo "✗ Failed to generate DSQL auth token: ${AURORA_PASSWORD}"
      FAILED=$((FAILED + 1))
      AURORA_ENDPOINT=""
    }
    AURORA_USER="admin"
    AURORA_DB="postgres"
    SEED_SQL="${SCRIPT_DIR}/seed-aurora-dsql.sql"
  else
    SEED_SQL="${SCRIPT_DIR}/seed-aurora.sql"
  fi

  if [ -n "${AURORA_ENDPOINT:-}" ]; then
    run_step "Aurora" \
      "PGSSLMODE=require PGPASSWORD=\${AURORA_PASSWORD} psql -h \${AURORA_ENDPOINT} -U \${AURORA_USER:-mall_admin} -d \${AURORA_DB:-mall} -f \${SEED_SQL}"
  fi
else
  echo "⏭ Skipping Aurora (AURORA_ENDPOINT not set)"
  echo ""
fi

# ── Step 2: DocumentDB (MongoDB) ───────────────────────────────────────────
# Build URI from individual env vars if DOCUMENTDB_URI is not set
if [ -z "${DOCUMENTDB_URI:-}" ] && [ -n "${DOCUMENTDB_HOST:-}" ]; then
  DOCUMENTDB_URI="mongodb://${DOCUMENTDB_USER:-docdb_admin}:${DOCUMENTDB_PASSWORD}@${DOCUMENTDB_HOST}:${DOCUMENTDB_PORT:-27017}/${DOCUMENTDB_DB:-mall}?tls=true&replicaSet=rs0&readPreference=secondaryPreferred&retryWrites=false&authMechanism=SCRAM-SHA-1"
  export DOCUMENTDB_URI
fi

if [ -n "${DOCUMENTDB_URI:-}" ]; then
  run_step "DocumentDB" \
    "node ${SCRIPT_DIR}/seed-documentdb.js"
else
  echo "⏭ Skipping DocumentDB (DOCUMENTDB_URI not set)"
  echo ""
fi

# ── Step 3: OpenSearch ──────────────────────────────────────────────────────
if [ -n "${OPENSEARCH_ENDPOINT:-}" ]; then
  run_step "OpenSearch" \
    "bash ${SCRIPT_DIR}/seed-opensearch.sh"
else
  echo "⏭ Skipping OpenSearch (OPENSEARCH_ENDPOINT not set)"
  echo ""
fi

# ── Step 4: MSK (Kafka Topics) ─────────────────────────────────────────────
if [ -n "${MSK_BOOTSTRAP:-}" ]; then
  run_step "MSK Topics" \
    "bash ${SCRIPT_DIR}/seed-kafka-topics.sh"
else
  echo "⏭ Skipping MSK (MSK_BOOTSTRAP not set)"
  echo ""
fi

# ── Step 5: ElastiCache (Valkey/Redis) ──────────────────────────────────────
if [ -n "${ELASTICACHE_ENDPOINT:-}" ]; then
  run_step "ElastiCache" \
    "bash ${SCRIPT_DIR}/seed-redis.sh"
else
  echo "⏭ Skipping ElastiCache (ELASTICACHE_ENDPOINT not set)"
  echo ""
fi

# ── Summary ─────────────────────────────────────────────────────────────────
echo "============================================"
echo " Seed Summary"
echo "============================================"
echo " Succeeded: ${SUCCEEDED}"
echo " Failed:    ${FAILED}"
echo " Skipped:   $((5 - SUCCEEDED - FAILED))"
echo "============================================"

if [ "$FAILED" -gt 0 ]; then
  exit 1
fi
