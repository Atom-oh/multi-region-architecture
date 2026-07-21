#!/bin/bash
# package-dataset.sh — Bundle the crawled product dataset (JSON + images) into a
# zip and publish it to S3 so it's downloadable via CloudFront without re-crawling.
#
#   bash scripts/seed-data/package-dataset.sh
#
# Result: https://mall.atomai.click/datasets/mall-seed-dataset.zip
#
# Why: products-1000.json hotlinks every image from third-party CDNs
# (img.danuri.io / Danawa / Amazon / Unsplash). Those links rot; re-crawling is
# the only recovery. This snapshots the images once while the links still work.
# CloudFront needs NO config change — the default cache behavior already routes
# any non-/api/*, non-/static/* path to the static-assets S3 origin.
set -euo pipefail

REGION="${AWS_REGION:-ap-northeast-2}"
BUCKET="${DATASET_BUCKET:-production-mall-static-assets-ap-northeast-2}"
S3_KEY="datasets/mall-seed-dataset.zip"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PRODUCTS_JSON="$SCRIPT_DIR/products-1000.json"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

mkdir -p "$WORK_DIR/dataset/images"
cp "$PRODUCTS_JSON" "$WORK_DIR/dataset/"

# ── 1. Extract (productId, index, url) triples ──────────────────────────────
python3 - "$PRODUCTS_JSON" > "$WORK_DIR/urls.tsv" <<'PY'
import json, sys
for p in json.load(open(sys.argv[1])):
    for i, url in enumerate(p.get("images", [])):
        if url.startswith("http"):
            print(f'{p["productId"]}\t{i}\t{url}')
PY
TOTAL=$(wc -l < "$WORK_DIR/urls.tsv")
echo "Downloading $TOTAL images..."

# ── 2. Download (skip failures — some CDN links may already be dead) ────────
OK=0; FAIL=0
while IFS=$'\t' read -r pid idx url; do
  # extension from URL path, default jpg
  ext="${url%%\?*}"; ext="${ext##*.}"
  case "$ext" in jpg|jpeg|png|webp|gif) ;; *) ext="jpg" ;; esac
  if curl -fsSL --retry 2 --max-time 30 -o "$WORK_DIR/dataset/images/${pid}-${idx}.${ext}" "$url"; then
    OK=$((OK+1))
  else
    FAIL=$((FAIL+1)); echo "SKIP (dead link): $pid $url"
  fi
done < "$WORK_DIR/urls.tsv"
echo "Downloaded: $OK, failed: $FAIL / $TOTAL"

cat > "$WORK_DIR/dataset/README.md" <<EOF
# VELLURE mall seed dataset

- products-1000.json — 1000 crawled products (source of truth for all data stores)
- images/<productId>-<n>.<ext> — snapshot of each product's images[n] URL,
  taken $(date -u +%Y-%m-%d) ($OK/$TOTAL succeeded)

The JSON still references the original CDN URLs; use these files as the
fallback when those links rot.
EOF

# ── 3. Zip + upload ──────────────────────────────────────────────────────────
(cd "$WORK_DIR" && zip -qr mall-seed-dataset.zip dataset)
echo "Zip size: $(du -h "$WORK_DIR/mall-seed-dataset.zip" | cut -f1)"

aws s3 cp "$WORK_DIR/mall-seed-dataset.zip" "s3://$BUCKET/$S3_KEY" \
  --region "$REGION" \
  --content-type application/zip \
  --content-disposition 'attachment; filename="mall-seed-dataset.zip"'

echo ""
echo "Done. Download URL:"
echo "  https://mall.atomai.click/$S3_KEY"
