#!/bin/bash
# ============================================================================
# Upload product images to S3 for CloudFront serving.
#
# Source priority per product:
#   1. $LOCAL_IMAGES_DIR/<productId>-<n>.<ext>  (pre-fetched snapshot, no
#      external network calls — see scripts/seed-data dataset snapshot)
#   2. images_sources[]/images[] URLs in products-1000.json (live download,
#      requires a browser-like User-Agent + Referer or most CDNs 403/hotlink-block)
#
# Usage: LOCAL_IMAGES_DIR=/path/to/images bash scripts/upload-product-images.sh [--dry-run]
#
# Prerequisites: aws cli, jq, curl
# ============================================================================

set -euo pipefail

REGION="ap-northeast-2"
S3_BUCKET="production-mall-static-assets-ap-northeast-2"
PRODUCTS_JSON="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/seed-data/products-1000.json"
LOCAL_IMAGES_DIR="${LOCAL_IMAGES_DIR:-}"
TMP_DIR=$(mktemp -d)
PARALLEL="${PARALLEL:-10}"
DRY_RUN="${1:-}"
CF_DISTRIBUTION_ID="${CF_DISTRIBUTION_ID:-EPOSH8YXOTOFZ}"
UPLOADED=0
FAILED=0
SKIPPED=0

trap "rm -rf $TMP_DIR" EXIT

echo "============================================"
echo " Product Image Upload to S3"
echo " Bucket: ${S3_BUCKET}"
echo " Region: ${REGION}"
echo " Source: ${PRODUCTS_JSON}"
echo " Local image dir: ${LOCAL_IMAGES_DIR:-<none, will download>}"
echo "============================================"
echo ""

if [ ! -f "$PRODUCTS_JSON" ]; then
  echo "ERROR: products-1000.json not found at ${PRODUCTS_JSON}"
  echo "Run crawl-products.py first to generate product data."
  exit 1
fi

TOTAL=$(jq 'length' "$PRODUCTS_JSON")
echo "Found ${TOTAL} products to process"
echo ""

upload_one() {
  local product_id="$1"
  local variant="$2"  # thumb, main, alt
  local local_index="$3"
  local url="$4"
  local s3_key="images/products/${product_id}/${variant}.jpg"

  if aws s3api head-object --bucket "$S3_BUCKET" --key "$s3_key" --region "$REGION" >/dev/null 2>&1; then
    return 0
  fi

  if [ "$DRY_RUN" = "--dry-run" ]; then
    echo "  [DRY-RUN] Would upload -> s3://${S3_BUCKET}/${s3_key}"
    return 0
  fi

  local local_file=""
  if [ -n "$LOCAL_IMAGES_DIR" ]; then
    for ext in jpg jpeg png webp; do
      candidate="${LOCAL_IMAGES_DIR}/${product_id}-${local_index}.${ext}"
      if [ -f "$candidate" ]; then
        local_file="$candidate"
        break
      fi
    done
  fi

  local downloaded=0
  if [ -z "$local_file" ]; then
    [ -z "$url" ] && return 1
    local_file="${TMP_DIR}/${product_id}-${variant}.jpg"
    if ! curl -sSfL -A "Mozilla/5.0" -H "Referer: https://mall.atomai.click/" -o "$local_file" "$url" 2>/dev/null; then
      echo "  [WARN] Failed to download: ${url}"
      return 1
    fi
    downloaded=1
  fi

  if aws s3 cp "$local_file" "s3://${S3_BUCKET}/${s3_key}" \
    --region "$REGION" \
    --cache-control "public, max-age=31536000, immutable" \
    --content-type "image/jpeg" \
    --quiet; then
    [ "$downloaded" = "1" ] && rm -f "$local_file"
    return 0
  else
    echo "  [WARN] Failed to upload: ${s3_key}"
    [ "$downloaded" = "1" ] && rm -f "$local_file"
    return 1
  fi
}

export -f upload_one
export S3_BUCKET REGION TMP_DIR DRY_RUN LOCAL_IMAGES_DIR

for i in $(seq 0 $((TOTAL - 1))); do
  PRODUCT_ID=$(jq -r ".[$i].productId" "$PRODUCTS_JSON")
  [ -z "$PRODUCT_ID" ] || [ "$PRODUCT_ID" = "null" ] && continue

  SOURCES=$(jq -r ".[$i].image_sources[]? // .[$i].images[]?" "$PRODUCTS_JSON" 2>/dev/null)

  IDX=0
  while IFS= read -r img_url; do
    case $IDX in
      0) VARIANT="thumb" ;;
      1) VARIANT="main" ;;
      2) VARIANT="alt" ;;
      *) IDX=$((IDX + 1)); continue ;;
    esac

    if upload_one "$PRODUCT_ID" "$VARIANT" "$IDX" "$img_url"; then
      UPLOADED=$((UPLOADED + 1))
    else
      FAILED=$((FAILED + 1))
    fi
    IDX=$((IDX + 1))
  done <<< "$SOURCES"

  # At minimum always populate thumb+main from local index 0 even if the
  # product only has a single source image (mirror it to both variants so
  # the frontend's thumb/main split never 404s).
  if [ -n "$LOCAL_IMAGES_DIR" ]; then
    N_SOURCES=$(echo "$SOURCES" | grep -c . || true)
    if [ "$N_SOURCES" -le 1 ]; then
      if upload_one "$PRODUCT_ID" "main" "0" ""; then
        UPLOADED=$((UPLOADED + 1))
      fi
    fi
  fi

  if [ $(((i + 1) % 100)) -eq 0 ]; then
    echo "  Progress: $((i + 1))/${TOTAL} products processed (${UPLOADED} uploaded, ${FAILED} failed)"
  fi
done

echo ""
echo "============================================"
echo " Upload Summary"
echo "============================================"
echo " Total products: ${TOTAL}"
echo " Images uploaded: ${UPLOADED}"
echo " Failed: ${FAILED}"
echo "============================================"

if [ "$FAILED" -gt 0 ]; then
  echo ""
  echo "Some images failed to upload. Re-run the script to retry (already-uploaded keys are skipped)."
fi

if [ "$DRY_RUN" != "--dry-run" ] && [ "$UPLOADED" -gt 0 ]; then
  echo ""
  echo "Invalidating CloudFront cache for /images/products/*..."
  aws cloudfront create-invalidation \
    --distribution-id "$CF_DISTRIBUTION_ID" \
    --paths "/images/products/*" \
    --query 'Invalidation.Id' --output text
fi
