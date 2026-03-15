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

# ── Step 1: Aurora PostgreSQL ───────────────────────────────────────────────
if [ -n "${AURORA_ENDPOINT:-}" ]; then
  run_step "Aurora PostgreSQL" \
    "PGPASSWORD=\${AURORA_PASSWORD} psql -h \${AURORA_ENDPOINT} -U \${AURORA_USER:-mall_admin} -d \${AURORA_DB:-mall} -f ${SCRIPT_DIR}/seed-aurora.sql"
else
  echo "⏭ Skipping Aurora (AURORA_ENDPOINT not set)"
  echo ""
fi

# ── Step 2: DocumentDB (MongoDB) ───────────────────────────────────────────
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
