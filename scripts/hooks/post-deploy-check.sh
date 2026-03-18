#!/bin/bash
#
# Claude Code PostToolUse hook — checks mall.atomai.click after deployment commands
#
# Receives JSON on stdin with: tool_name, tool_input.command, tool_response
# Only runs the check when the Bash command matches deployment patterns.

set -uo pipefail

# Read hook input from stdin
INPUT=$(cat)

# Extract the command that was executed
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)

if [[ -z "$COMMAND" ]]; then
  exit 0
fi

# Only trigger on deployment-related commands
DEPLOY_PATTERNS=(
  "terraform apply"
  "kubectl apply"
  "kubectl rollout"
  "argocd app sync"
  "helm install"
  "helm upgrade"
)

IS_DEPLOY=false
for PATTERN in "${DEPLOY_PATTERNS[@]}"; do
  if echo "$COMMAND" | grep -qi "$PATTERN"; then
    IS_DEPLOY=true
    break
  fi
done

if [[ "$IS_DEPLOY" != "true" ]]; then
  exit 0
fi

# --- Deployment detected: run connectivity check ---

MALL_URL="https://mall.atomai.click"
CF_URL="https://d1muyxliujbszf.cloudfront.net"
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

echo ""
echo "=== Post-Deployment Connectivity Check ==="
echo "Triggered by: $(echo "$COMMAND" | head -c 120)"
echo ""

# 1. Quick curl check on mall.atomai.click
HTTP_CODE=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "$MALL_URL/" 2>/dev/null || echo "000")
if [[ "$HTTP_CODE" == "200" ]]; then
  echo "PASS: $MALL_URL returned HTTP $HTTP_CODE"
elif [[ "$HTTP_CODE" == "403" || "$HTTP_CODE" == "502" || "$HTTP_CODE" == "503" ]]; then
  echo "WARN: $MALL_URL returned HTTP $HTTP_CODE (pods may not be ready yet)"
elif [[ "$HTTP_CODE" == "000" ]]; then
  echo "FAIL: $MALL_URL connection timeout"
else
  echo "INFO: $MALL_URL returned HTTP $HTTP_CODE"
fi

# 2. Quick curl check on CloudFront directly
CF_CODE=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "$CF_URL/" 2>/dev/null || echo "000")
if [[ "$CF_CODE" == "200" ]]; then
  echo "PASS: CloudFront returned HTTP $CF_CODE"
elif [[ "$CF_CODE" == "403" || "$CF_CODE" == "502" || "$CF_CODE" == "503" ]]; then
  echo "WARN: CloudFront returned HTTP $CF_CODE (pods may not be ready yet)"
elif [[ "$CF_CODE" == "000" ]]; then
  echo "FAIL: CloudFront connection timeout"
else
  echo "INFO: CloudFront returned HTTP $CF_CODE"
fi

# 3. Suggest full test if issues detected
if [[ "$HTTP_CODE" != "200" || "$CF_CODE" != "200" ]]; then
  echo ""
  echo "Run full verification: bash scripts/test-traffic-flow.sh"
fi

echo "==========================================="
echo ""
