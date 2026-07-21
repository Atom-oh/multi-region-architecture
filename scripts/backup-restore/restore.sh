#!/bin/bash
# ============================================================================
# Multi-Region Shopping Mall - Data Restore
#
# Reverse of backup.sh: restores Aurora (pg_restore) + DocumentDB
# (mongorestore) + S3 product images from an archive produced by backup.sh.
# Run this AFTER terraform apply has created the target environment's
# data stores. Valkey/MSK/OpenSearch are not in the archive — re-seed them
# with scripts/seed-data/ (seed-redis.sh, seed-kafka-topics.sh,
# seed-opensearch.sh) after this script finishes.
#
# Env vars (same convention as backup.sh / scripts/seed-data/run-seed.sh):
#   ARCHIVE_PATH (required)          — local path to the mall-data-backup-*.tar.gz,
#                                       or set ARCHIVE_S3_URI to download it first
#   ARCHIVE_S3_URI                   — s3://bucket/key to fetch ARCHIVE_PATH from
#   AURORA_ENDPOINT, AURORA_USER, AURORA_PASSWORD, AURORA_DB
#   DOCUMENTDB_URI (or DOCUMENTDB_HOST/USER/PASSWORD/DB/PORT)
#     DOCUMENTDB_DB must match the SOURCE db name the archive was dumped
#     from (both are "mall" by default) — mongorestore's --archive mode
#     restores into the namespace names baked into the archive itself, and
#     an unrelated DOCUMENTDB_DB here acts as a filter that just excludes
#     everything, silently restoring 0 documents.
#   STATIC_ASSETS_BUCKET              — target bucket for restored images
# ============================================================================

set -euo pipefail

WORKDIR="$(mktemp -d)"
trap 'rm -rf "${WORKDIR}"' EXIT

echo "============================================"
echo " Shopping Mall - Data Restore"
echo " Time:   $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "============================================"

if [ -n "${ARCHIVE_S3_URI:-}" ]; then
  ARCHIVE_PATH="${WORKDIR}/$(basename "${ARCHIVE_S3_URI}")"
  echo "▶ Downloading ${ARCHIVE_S3_URI}"
  aws s3 cp "${ARCHIVE_S3_URI}" "${ARCHIVE_PATH}"
fi

: "${ARCHIVE_PATH:?Set ARCHIVE_PATH or ARCHIVE_S3_URI}"

echo "▶ Unpacking ${ARCHIVE_PATH}"
tar xzf "${ARCHIVE_PATH}" -C "${WORKDIR}"

if [ -f "${WORKDIR}/manifest.json" ]; then
  echo "--- manifest.json ---"
  cat "${WORKDIR}/manifest.json"
  echo "---------------------"
fi

FAILED=0

# ── Aurora PostgreSQL ────────────────────────────────────────────────────────
if [ -n "${AURORA_ENDPOINT:-}" ] && [ -f "${WORKDIR}/aurora/aurora.dump" ]; then
  echo "▶ Aurora: pg_restore -> ${AURORA_ENDPOINT}"
  if PGSSLMODE=require PGPASSWORD="${AURORA_PASSWORD:-}" pg_restore \
      -h "${AURORA_ENDPOINT}" -U "${AURORA_USER:-mall_admin}" -d "${AURORA_DB:-mall}" \
      --clean --if-exists --no-owner "${WORKDIR}/aurora/aurora.dump"; then
    echo "✓ Aurora restored"
  else
    echo "✗ Aurora restore FAILED (continuing)"
    FAILED=$((FAILED + 1))
  fi
else
  echo "⏭ Skipping Aurora (AURORA_ENDPOINT not set or no dump in archive)"
fi

# ── DocumentDB (MongoDB) ─────────────────────────────────────────────────────
if [ -z "${DOCUMENTDB_URI:-}" ] && [ -n "${DOCUMENTDB_HOST:-}" ]; then
  DOCUMENTDB_URI="mongodb://${DOCUMENTDB_USER:-docdb_admin}:${DOCUMENTDB_PASSWORD}@${DOCUMENTDB_HOST}:${DOCUMENTDB_PORT:-27017}/${DOCUMENTDB_DB:-mall}?tls=true&readPreference=secondaryPreferred&retryWrites=false"
fi

if [ -n "${DOCUMENTDB_URI:-}" ] && [ -f "${WORKDIR}/documentdb/documentdb.archive.gz" ]; then
  echo "▶ DocumentDB: mongorestore"
  if mongorestore --uri="${DOCUMENTDB_URI}" --tlsInsecure \
      --archive="${WORKDIR}/documentdb/documentdb.archive.gz" --gzip --drop; then
    echo "✓ DocumentDB restored"
  else
    echo "✗ DocumentDB restore FAILED (continuing)"
    FAILED=$((FAILED + 1))
  fi
else
  echo "⏭ Skipping DocumentDB (DOCUMENTDB_URI/DOCUMENTDB_HOST not set or no archive)"
fi

# ── S3 static assets (product images) ────────────────────────────────────────
if [ -n "${STATIC_ASSETS_BUCKET:-}" ] && [ -d "${WORKDIR}/s3-static-assets" ]; then
  echo "▶ S3: uploading to s3://${STATIC_ASSETS_BUCKET}"
  if aws s3 sync "${WORKDIR}/s3-static-assets/" "s3://${STATIC_ASSETS_BUCKET}" --only-show-errors; then
    echo "✓ S3 uploaded"
  else
    echo "✗ S3 upload FAILED (continuing)"
    FAILED=$((FAILED + 1))
  fi
else
  echo "⏭ Skipping S3 (STATIC_ASSETS_BUCKET not set or no images in archive)"
fi

echo "============================================"
echo " Restore complete. Failed steps: ${FAILED}"
echo " Next: re-seed Valkey/MSK/OpenSearch via scripts/seed-data/"
echo "============================================"

[ "$FAILED" -eq 0 ]
