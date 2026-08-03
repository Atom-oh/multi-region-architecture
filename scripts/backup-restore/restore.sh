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
#   ALLOW_PARTIAL_RESTORE=1           — proceed even though the archive's
#                                       manifest records failed/skipped
#                                       targets (default: refuse)
# ============================================================================

set -euo pipefail

# ── Guards (pure-ish helpers so `restore.sh --self-check` can exercise them) ──

# Host out of a mongodb:// URI. Greedy ##*@ so a password containing '@'
# doesn't truncate the host; then strip the :port and /db tail.
docdb_host_from_uri() {
  local rest="${1#mongodb://}"
  rest="${rest#mongodb+srv://}"
  rest="${rest##*@}"
  rest="${rest%%/*}"
  rest="${rest%%\?*}"
  echo "${rest%%:*}"
}

# Refuse an archive whose manifest records a target that didn't make it.
# restore.sh is destructive (pg_restore --clean, mongorestore --drop): restoring
# a half-written archive silently replaces good data with less data.
assert_manifest_complete() {
  local manifest=$1
  if [ ! -f "$manifest" ]; then
    echo "✗ ABORT: no manifest.json in the archive — can't tell whether the"
    echo "  backup completed. Set ALLOW_PARTIAL_RESTORE=1 to override."
    return 1
  fi
  local bad
  bad=$(grep -oE '"[a-z_0-9]+": \{"status": "(failed|skipped)"' "$manifest" || true)
  if [ -n "$bad" ]; then
    echo "✗ ABORT: archive is incomplete — these targets are not in it:"
    echo "$bad" | sed 's/^/    /'
    echo "  Restoring it would wipe live data and replace it with a partial copy."
    echo "  Set ALLOW_PARTIAL_RESTORE=1 if that is genuinely what you want."
    return 1
  fi
  return 0
}

# Never restore into a read-only DocumentDB global-cluster secondary. Korea's
# DocumentDB is one (see docs/portability-assessment.md): writes are rejected at
# the storage layer, so `mongorestore --drop` fails AFTER Aurora was already
# wiped and restored, leaving the stores inconsistent — exactly what this guard
# exists to prevent. Fail closed: if the topology can't be determined, abort.
assert_docdb_writable() {
  local host=$1 arns
  local cluster_id="${host%%.*}"
  if ! arns=$(aws docdb describe-global-clusters \
      --query 'GlobalClusters[].GlobalClusterMembers[?IsWriter==`false`].DBClusterArn[]' \
      --output text 2>&1); then
    echo "✗ ABORT: could not determine DocumentDB global-cluster topology:"
    echo "    ${arns}"
    echo "  Refusing to run a destructive restore blind (needs"
    echo "  rds:DescribeGlobalClusters). Fix credentials/IAM and re-run."
    return 1
  fi
  if echo "${arns}" | tr '\t' '\n' | grep -q ":cluster:${cluster_id}$"; then
    echo "✗ ABORT: DocumentDB target '${cluster_id}' is a read-only global-cluster"
    echo "  secondary — mongorestore would fail and leave Aurora/DocumentDB inconsistent."
    echo "  Promote it first: aws docdb remove-from-global-cluster ... (then re-run)."
    return 1
  fi
  return 0
}

# ── Self-check: the guards above are the only thing standing between a typo
# and a wiped database, so they get a runnable test. `bash restore.sh --self-check`
if [ "${1:-}" = "--self-check" ]; then
  fail=0
  check() { # check <desc> <expected> <actual>
    if [ "$2" = "$3" ]; then echo "  ok   $1"; else
      echo "  FAIL $1: expected '$2', got '$3'"; fail=1; fi
  }
  echo "docdb_host_from_uri:"
  check "plain host" "db.example.com" \
    "$(docdb_host_from_uri 'mongodb://u:p@db.example.com:27017/mall?tls=true')"
  check "password containing @" "db.example.com" \
    "$(docdb_host_from_uri 'mongodb://u:p@ss@db.example.com:27017/mall')"
  check "no port, no db" "db.example.com" \
    "$(docdb_host_from_uri 'mongodb://u:p@db.example.com')"
  echo "assert_manifest_complete:"
  tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
  printf '{"targets": {\n    "aurora": {"status": "ok", "detail": []},\n    "documentdb": {"status": "ok", "detail": ""}\n}}\n' > "$tmp/ok.json"
  printf '{"targets": {\n    "aurora": {"status": "ok", "detail": []},\n    "documentdb": {"status": "failed", "detail": ""}\n}}\n' > "$tmp/failed.json"
  printf '{"targets": {\n    "aurora": {"status": "skipped", "detail": ""}\n}}\n' > "$tmp/skipped.json"
  check "complete manifest passes" "0" \
    "$(assert_manifest_complete "$tmp/ok.json" >/dev/null; echo $?)"
  check "failed target aborts" "1" \
    "$(assert_manifest_complete "$tmp/failed.json" >/dev/null; echo $?)"
  check "skipped target aborts" "1" \
    "$(assert_manifest_complete "$tmp/skipped.json" >/dev/null; echo $?)"
  check "missing manifest aborts" "1" \
    "$(assert_manifest_complete "$tmp/nope.json" >/dev/null; echo $?)"
  [ "$fail" -eq 0 ] && echo "self-check PASSED" || echo "self-check FAILED"
  exit "$fail"
fi

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

# ── Build DOCUMENTDB_URI here, not next to the mongorestore call, so the guard
# below sees the same target the restore will use. ──────────────────────────
if [ -z "${DOCUMENTDB_URI:-}" ] && [ -n "${DOCUMENTDB_HOST:-}" ]; then
  DOCUMENTDB_URI="mongodb://${DOCUMENTDB_USER:-docdb_admin}:${DOCUMENTDB_PASSWORD}@${DOCUMENTDB_HOST}:${DOCUMENTDB_PORT:-27017}/${DOCUMENTDB_DB:-mall}?tls=true&readPreference=secondaryPreferred&retryWrites=false"
fi

# ── ALL safety checks run before ANY destructive step ───────────────────────
# Everything below this point wipes data (pg_restore --clean, mongorestore
# --drop, s3 sync --delete). Anything that can abort must abort here, while
# the target is still intact.
if [ "${ALLOW_PARTIAL_RESTORE:-0}" = "1" ]; then
  echo "⚠ ALLOW_PARTIAL_RESTORE=1 — skipping the archive-completeness check"
else
  assert_manifest_complete "${WORKDIR}/manifest.json" || exit 1
fi

# Derive the host from whichever input was used — DOCUMENTDB_URI alone is a
# documented, supported path, and it used to bypass this guard entirely.
if [ -n "${DOCUMENTDB_URI:-}" ]; then
  DOCDB_HOST="$(docdb_host_from_uri "${DOCUMENTDB_URI}")"
  if [ -z "${DOCDB_HOST}" ]; then
    echo "✗ ABORT: could not parse a host out of DOCUMENTDB_URI — the read-only"
    echo "  secondary check can't run, and it is not safe to skip."
    exit 1
  fi
  assert_docdb_writable "${DOCDB_HOST}" || exit 1
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
# (DOCUMENTDB_URI was built above, before the guards.)
if [ -n "${DOCUMENTDB_URI:-}" ] && [ -f "${WORKDIR}/documentdb/documentdb.archive.gz" ]; then
  echo "▶ DocumentDB: mongorestore"
  if mongorestore --uri="${DOCUMENTDB_URI}" \
      --tlsCAFile=/etc/ssl/certs/rds-global-bundle.pem \
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
  # --delete: a restore must reproduce the snapshot, not merge into whatever is
  # there. Without it, objects deleted since the backup survive the "restore".
  # backup.sh excludes backups/*, so this deliberately excludes it too —
  # otherwise restoring into a bucket that doubles as the archive store would
  # delete the very archive being restored from.
  if aws s3 sync "${WORKDIR}/s3-static-assets/" "s3://${STATIC_ASSETS_BUCKET}" \
      --delete --exclude "backups/*" --only-show-errors; then
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
