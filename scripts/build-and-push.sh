#!/bin/bash
set -e

ACCOUNT_ID="123456789012"
REGION="us-east-1"
ECR_PREFIX="shopping-mall"
TAG="${1:-latest}"
SRC_DIR="/home/ec2-user/multi-region-architecture/src"

echo "Building and pushing all services to ECR (amd64)..."

aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com

build_go_service() {
    local svc=$1
    local ecr_uri="$ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/$ECR_PREFIX/$svc:$TAG"
    echo "=== Building Go service: $svc ==="
    docker build -t "$svc:$TAG" -f "$SRC_DIR/services/$svc/Dockerfile" "$SRC_DIR" || { echo "FAILED: $svc build"; return 1; }
    docker tag "$svc:$TAG" "$ecr_uri"
    docker push "$ecr_uri" || { echo "FAILED: $svc push"; return 1; }
    echo "=== $svc pushed ==="
}

build_python_service() {
    local svc=$1
    local ecr_uri="$ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/$ECR_PREFIX/$svc:$TAG"
    echo "=== Building Python service: $svc ==="
    cd "$SRC_DIR/services/$svc"
    rm -rf mall_common 2>/dev/null || true
    cp -r "$SRC_DIR/shared/python/mall_common" .
    docker build -t "$svc:$TAG" . || { echo "FAILED: $svc build"; return 1; }
    docker tag "$svc:$TAG" "$ecr_uri"
    docker push "$ecr_uri" || { echo "FAILED: $svc push"; return 1; }
    echo "=== $svc pushed ==="
    rm -rf mall_common
}

build_java_service() {
    local svc=$1
    local ecr_uri="$ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/$ECR_PREFIX/$svc:$TAG"
    echo "=== Building Java service: $svc ==="
    docker build -t "$svc:$TAG" -f "$SRC_DIR/services/$svc/Dockerfile" "$SRC_DIR" || { echo "FAILED: $svc build"; return 1; }
    docker tag "$svc:$TAG" "$ecr_uri"
    docker push "$ecr_uri" || { echo "FAILED: $svc push"; return 1; }
    echo "=== $svc pushed ==="
}

# Go Services (5)
for svc in api-gateway event-bus cart search inventory; do build_go_service "$svc"; done

# Python Services (8)
for svc in product-catalog analytics user-profile wishlist review shipping recommendation notification; do build_python_service "$svc"; done

# Java Services (7)
for svc in order payment user-account warehouse returns pricing seller; do build_java_service "$svc"; done

# Synthetic Monitor (standalone Python — no mall_common)
build_standalone_python() {
    local svc=$1
    local ecr_uri="$ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/$ECR_PREFIX/$svc:$TAG"
    echo "=== Building standalone Python: $svc ==="
    cd "$SRC_DIR/$svc"
    docker build -t "$svc:$TAG" . || { echo "FAILED: $svc build"; return 1; }
    docker tag "$svc:$TAG" "$ecr_uri"
    docker push "$ecr_uri" || { echo "FAILED: $svc push"; return 1; }
    echo "=== $svc pushed ==="
}
build_standalone_python "synthetic-monitor"

echo ""
echo "=== All services built and pushed successfully ==="
