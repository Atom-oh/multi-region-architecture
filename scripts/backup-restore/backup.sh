#!/bin/bash
# ============================================================================
# Multi-Region Shopping Mall - Data Backup
#
# Backs up only what code can't regenerate: Aurora (pg_dump), DocumentDB
# (mongodump), and S3 product images. Valkey/MSK/OpenSearch are skipped —
# restore.sh re-seeds them via scripts/seed-data/ instead.
#
# Env vars (same convention as scripts/seed-data/run-seed.sh):
#   AURORA_ENDPOINT, AURORA_USER, AURORA_PASSWORD, AURORA_DB
#   DOCUMENTDB_URI (or DOCUMENTDB_HOST/USER/PASSWORD/DB/PORT)
#   STATIC_ASSETS_BUCKET
#   BACKUP_S3_BUCKET, BACKUP_S3_PREFIX (default "backups")
#   REGION_LABEL (free-form tag for the archive filename, e.g. "ap-northeast-2")
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REGION_LABEL="${REGION_LABEL:-${AWS_REGION:-unknown}}"
TIMESTAMP="$(date -u +%Y%m%dT%H%M%SZ)"
WORKDIR="$(mktemp -d)"
ARCHIVE_NAME="mall-data-backup-${REGION_LABEL}-${TIMESTAMP}.tar.gz"

mkdir -p "${WORKDIR}/aurora" "${WORKDIR}/documentdb" "${WORKDIR}/s3-static-assets"

echo "============================================"
echo " Shopping Mall - Data Backup"
echo " Region: ${REGION_LABEL}"
echo " Time:   ${TIMESTAMP}"
echo "============================================"

MANIFEST="${WORKDIR}/manifest.json"
echo "{" > "${MANIFEST}"
echo "  \"timestamp\": \"${TIMESTAMP}\"," >> "${MANIFEST}"
echo "  \"region_label\": \"${REGION_LABEL}\"," >> "${MANIFEST}"
echo "  \"targets\": {" >> "${MANIFEST}"

FIRST_TARGET=1
FAILED=0
add_target() {
  local name=$1 status=$2 detail=$3
  [ "$FIRST_TARGET" -eq 1 ] || echo "," >> "${MANIFEST}"
  FIRST_TARGET=0
  printf '    "%s": {"status": "%s", "detail": %s}' "$name" "$status" "$detail" >> "${MANIFEST}"
}

# ── Aurora PostgreSQL ────────────────────────────────────────────────────────
if [ -n "${AURORA_ENDPOINT:-}" ]; then
  echo "▶ Aurora: pg_dump ${AURORA_ENDPOINT}"
  if PGSSLMODE=require PGPASSWORD="${AURORA_PASSWORD:-}" pg_dump \
      -h "${AURORA_ENDPOINT}" -U "${AURORA_USER:-mall_admin}" -d "${AURORA_DB:-mall}" \
      -Fc -f "${WORKDIR}/aurora/aurora.dump" 2>"${WORKDIR}/aurora/pg_dump.log"; then
    ROWCOUNTS=$(PGSSLMODE=require PGPASSWORD="${AURORA_PASSWORD:-}" psql \
      -h "${AURORA_ENDPOINT}" -U "${AURORA_USER:-mall_admin}" -d "${AURORA_DB:-mall}" \
      -Atc "select coalesce(json_agg(json_build_object('table', relname, 'approx_rows', n_live_tup)), '[]') from pg_stat_user_tables;" 2>/dev/null || echo '[]')
    add_target "aurora" "ok" "${ROWCOUNTS}"
    echo "✓ Aurora dumped"
  else
    add_target "aurora" "failed" "\"see aurora/pg_dump.log\""
    echo "✗ Aurora dump FAILED (continuing)"
    FAILED=$((FAILED + 1))
  fi
else
  add_target "aurora" "skipped" "\"AURORA_ENDPOINT not set\""
  echo "⏭ Skipping Aurora"
fi

# ── DocumentDB (MongoDB) ─────────────────────────────────────────────────────
if [ -z "${DOCUMENTDB_URI:-}" ] && [ -n "${DOCUMENTDB_HOST:-}" ]; then
  # No replicaSet= param: DocumentDB's actual replica set name isn't "rs0",
  # and asserting the wrong one makes mongo-tools' topology check hang until
  # it times out ("context deadline exceeded") instead of just connecting.
  DOCUMENTDB_URI="mongodb://${DOCUMENTDB_USER:-docdb_admin}:${DOCUMENTDB_PASSWORD}@${DOCUMENTDB_HOST}:${DOCUMENTDB_PORT:-27017}/${DOCUMENTDB_DB:-mall}?tls=true&readPreference=secondaryPreferred&retryWrites=false"
fi

if [ -n "${DOCUMENTDB_URI:-}" ]; then
  echo "▶ DocumentDB: mongodump"
  if mongodump --uri="${DOCUMENTDB_URI}" \
      --tlsCAFile=/etc/ssl/certs/rds-global-bundle.pem \
      --archive="${WORKDIR}/documentdb/documentdb.archive.gz" --gzip \
      2>"${WORKDIR}/documentdb/mongodump.log"; then
    DOC_SUMMARY=$(grep -oE "done dumping \`[^\`]+\` \([0-9]+ documents?\)" "${WORKDIR}/documentdb/mongodump.log" | sed -E 's/done dumping //' | paste -sd, - || echo "")
    add_target "documentdb" "ok" "\"${DOC_SUMMARY}\""
    echo "✓ DocumentDB dumped (${DOC_SUMMARY})"
  else
    add_target "documentdb" "failed" "\"see documentdb/mongodump.log\""
    echo "✗ DocumentDB dump FAILED (continuing)"
    FAILED=$((FAILED + 1))
  fi
else
  add_target "documentdb" "skipped" "\"DOCUMENTDB_URI/DOCUMENTDB_HOST not set\""
  echo "⏭ Skipping DocumentDB"
fi

# ── S3 static assets (product images) ────────────────────────────────────────
if [ -n "${STATIC_ASSETS_BUCKET:-}" ]; then
  echo "▶ S3: syncing s3://${STATIC_ASSETS_BUCKET}"
  # --exclude "backups/*": when BACKUP_S3_BUCKET is the same bucket as
  # STATIC_ASSETS_BUCKET, prior backup archives live under that prefix —
  # without the exclude, each backup would recursively swallow every
  # backup before it.
  if aws s3 sync "s3://${STATIC_ASSETS_BUCKET}" "${WORKDIR}/s3-static-assets/" --exclude "backups/*" --only-show-errors; then
    OBJECT_COUNT=$(find "${WORKDIR}/s3-static-assets" -type f | wc -l | tr -d ' ')
    add_target "s3_static_assets" "ok" "\"${OBJECT_COUNT} objects\""
    echo "✓ S3 synced (${OBJECT_COUNT} objects)"
  else
    add_target "s3_static_assets" "failed" "\"aws s3 sync errored\""
    echo "✗ S3 sync FAILED (continuing)"
    FAILED=$((FAILED + 1))
  fi
else
  add_target "s3_static_assets" "skipped" "\"STATIC_ASSETS_BUCKET not set\""
  echo "⏭ Skipping S3"
fi

echo "" >> "${MANIFEST}"
echo "  }" >> "${MANIFEST}"
echo "}" >> "${MANIFEST}"

echo "▶ Packing ${ARCHIVE_NAME}"
tar czf "/tmp/${ARCHIVE_NAME}" -C "${WORKDIR}" .
rm -rf "${WORKDIR}"

if [ -n "${BACKUP_S3_BUCKET:-}" ]; then
  DEST="s3://${BACKUP_S3_BUCKET}/${BACKUP_S3_PREFIX:-backups}/${ARCHIVE_NAME}"
  echo "▶ Uploading to ${DEST}"
  aws s3 cp "/tmp/${ARCHIVE_NAME}" "${DEST}"
  echo "✓ Uploaded: ${DEST}"
else
  echo "ℹ BACKUP_S3_BUCKET not set — archive left at /tmp/${ARCHIVE_NAME}"
fi

echo "============================================"
echo " Backup complete: ${ARCHIVE_NAME} (failed targets: ${FAILED})"
echo "============================================"

# A backup with failed targets must NOT look like a success — the archive is
# still uploaded (partial data beats none) but the Job exits non-zero so it
# can't be silently trusted as a restore point.
[ "$FAILED" -eq 0 ]
