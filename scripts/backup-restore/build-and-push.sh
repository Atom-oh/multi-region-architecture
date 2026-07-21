#!/bin/bash
# Build and push the backup-restore container image to ECR
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID:?Set AWS_ACCOUNT_ID env var}"
AWS_REGION="${AWS_REGION:-ap-northeast-2}"
ECR_REPO="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/shopping-mall/backup-restore"

echo "=== Building backup-restore image ==="
echo "ECR: ${ECR_REPO}"

aws ecr describe-repositories --repository-names shopping-mall/backup-restore --region "$AWS_REGION" 2>/dev/null || \
  aws ecr create-repository --repository-name shopping-mall/backup-restore --region "$AWS_REGION"

aws ecr get-login-password --region "$AWS_REGION" | docker login --username AWS --password-stdin "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

docker build -t backup-restore:latest "$SCRIPT_DIR"
docker tag backup-restore:latest "${ECR_REPO}:latest"
docker push "${ECR_REPO}:latest"

echo ""
echo "=== Done ==="
echo "Image: ${ECR_REPO}:latest"
echo ""
echo "To run a backup:"
echo "  kubectl delete job mall-backup -n core-services --ignore-not-found"
echo "  kubectl apply -f ${SCRIPT_DIR}/k8s/jobs/backup-job.yaml"
echo "  kubectl logs -f job/mall-backup -n core-services"
echo ""
echo "To restore (edit ARCHIVE_S3_URI / STATIC_ASSETS_BUCKET in restore-job.yaml first):"
echo "  kubectl apply -f ${SCRIPT_DIR}/k8s/jobs/restore-job.yaml"
echo "  kubectl logs -f job/mall-restore -n core-services"
