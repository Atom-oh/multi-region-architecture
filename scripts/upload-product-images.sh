#!/bin/bash
# ============================================================================
# Upload product images to S3 for CloudFront serving
# Downloads from Unsplash/picsum sources in products-1000.json,
# then uploads to S3 with proper cache headers.
#
# Usage: bash scripts/upload-product-images.sh [--dry-run]
#
# Prerequisites: aws cli, jq, curl
# ============================================================================

set -euo pipefail

REGION="us-east-1"
S3_BUCKET="production-mall-static-assets-us-east-1"
PRODUCTS_JSON="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/seed-data/products-1000.json"
TMP_DIR=$(mktemp -d)
PARALLEL="${PARALLEL:-10}"
DRY_RUN="${1:-}"
UPLOADED=0
FAILED=0
SKIPPED=0

trap "rm -rf $TMP_DIR" EXIT

echo "============================================"
echo " Product Image Upload to S3"
echo " Bucket: ${S3_BUCKET}"
echo " Region: ${REGION}"
echo " Source: ${PRODUCTS_JSON}"
echo "============================================"
echo ""

if [ ! -f "$PRODUCTS_JSON" ]; then
  echo "ERROR: products-1000.json not found at ${PRODUCTS_JSON}"
  echo "Run crawl-products.py first to generate product data."
  exit 1
fi

# Extract product IDs and image URLs from JSON
TOTAL=$(jq 'length' "$PRODUCTS_JSON")
echo "Found ${TOTAL} products to process"
echo ""

upload_image() {
  local product_id="$1"
  local url="$2"
  local variant="$3"  # thumb, main, alt
  local s3_key="images/products/${product_id}/${variant}.jpg"
  local local_file="${TMP_DIR}/${product_id}-${variant}.jpg"

  # Check if already exists in S3
  if aws s3api head-object --bucket "$S3_BUCKET" --key "$s3_key" --region "$REGION" >/dev/null 2>&1; then
    return 0  # Already exists, skip
  fi

  if [ "$DRY_RUN" = "--dry-run" ]; then
    echo "  [DRY-RUN] Would upload: ${url} → s3://${S3_BUCKET}/${s3_key}"
    return 0
  fi

  # Download
  if ! curl -sSfL -o "$local_file" "$url" 2>/dev/null; then
    echo "  [WARN] Failed to download: ${url}"
    return 1
  fi

  # Upload to S3 with immutable cache headers
  if aws s3 cp "$local_file" "s3://${S3_BUCKET}/${s3_key}" \
    --region "$REGION" \
    --cache-control "public, max-age=31536000, immutable" \
    --content-type "image/jpeg" \
    --quiet 2>/dev/null; then
    rm -f "$local_file"
    return 0
  else
    echo "  [WARN] Failed to upload: ${s3_key}"
    rm -f "$local_file"
    return 1
  fi
}

# Process each product
for i in $(seq 0 $((TOTAL - 1))); do
  PRODUCT_ID=$(jq -r ".[$i].productId" "$PRODUCTS_JSON")
  IMAGES=$(jq -r ".[$i].images[]?" "$PRODUCTS_JSON" 2>/dev/null)

  if [ -z "$PRODUCT_ID" ] || [ "$PRODUCT_ID" = "null" ]; then
    continue
  fi

  # Use image_sources (Unsplash/picsum URLs) as download source
  SOURCES=$(jq -r ".[$i].image_sources[]?" "$PRODUCTS_JSON" 2>/dev/null)
  if [ -z "$SOURCES" ]; then
    # Fallback to images field if image_sources not present
    SOURCES="$IMAGES"
  fi

  # Map images to variants: first=thumb, second=main, third=alt
  IDX=0
  while IFS= read -r img_url; do
    [ -z "$img_url" ] && continue
    case $IDX in
      0) VARIANT="thumb" ;;
      1) VARIANT="main" ;;
      2) VARIANT="alt" ;;
      *) continue ;;
    esac

    if upload_image "$PRODUCT_ID" "$img_url" "$VARIANT"; then
      UPLOADED=$((UPLOADED + 1))
    else
      FAILED=$((FAILED + 1))
    fi
    IDX=$((IDX + 1))
  done <<< "$SOURCES"

  # Progress every 100 products
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
  echo "Some images failed to upload. Re-run the script to retry."
fi
