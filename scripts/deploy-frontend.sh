#!/bin/bash
set -e

REGION="us-east-1"
S3_BUCKET="production-mall-static-assets-us-east-1"
CF_DISTRIBUTION="E2XBVTVYBYX8T6"
FRONTEND_DIR="/home/ec2-user/multi-region-architecture/src/frontend"

echo "=== Building frontend ==="
cd "$FRONTEND_DIR"
npm run build

echo "=== Syncing assets to S3 (with long cache for hashed files) ==="
aws s3 sync dist/ "s3://$S3_BUCKET/" \
  --region "$REGION" \
  --delete \
  --exclude "index.html" \
  --exclude "images/*" \
  --cache-control "public, max-age=31536000, immutable"

echo "=== Uploading index.html (no-cache to always serve latest) ==="
aws s3 cp dist/index.html "s3://$S3_BUCKET/index.html" \
  --region "$REGION" \
  --cache-control "no-cache, no-store, must-revalidate" \
  --content-type "text/html"

echo "=== Invalidating CloudFront ==="
INVALIDATION_ID=$(aws cloudfront create-invalidation \
  --distribution-id "$CF_DISTRIBUTION" \
  --paths "/*" \
  --region "$REGION" \
  --query 'Invalidation.Id' \
  --output text)

echo "Invalidation created: $INVALIDATION_ID"
echo "=== Frontend deployment complete ==="
