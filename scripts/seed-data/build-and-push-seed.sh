#!/bin/bash
# Build and push the seed-data container image to ECR
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID:?Set AWS_ACCOUNT_ID env var}"
AWS_REGION="${AWS_REGION:-us-east-1}"
ECR_REPO="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/shopping-mall/seed-data"

echo "=== Building seed-data image ==="
echo "ECR: ${ECR_REPO}"

# Create ECR repo if it doesn't exist
aws ecr describe-repositories --repository-names shopping-mall/seed-data --region "$AWS_REGION" 2>/dev/null || \
  aws ecr create-repository --repository-name shopping-mall/seed-data --region "$AWS_REGION"

# Login to ECR
aws ecr get-login-password --region "$AWS_REGION" | docker login --username AWS --password-stdin "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

# Build
docker build -t seed-data:latest "$SCRIPT_DIR"

# Tag & push
docker tag seed-data:latest "${ECR_REPO}:latest"
docker push "${ECR_REPO}:latest"

echo ""
echo "=== Done ==="
echo "Image: ${ECR_REPO}:latest"
echo ""
echo "To run the seed job:"
echo "  kubectl delete job seed-data -n platform --ignore-not-found"
echo "  kubectl apply -f ${SCRIPT_DIR}/k8s/jobs/seed-data-job.yaml"
echo "  kubectl logs -f job/seed-data -n platform"
