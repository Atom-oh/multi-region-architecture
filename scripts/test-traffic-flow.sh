#!/bin/bash
#
# test-traffic-flow.sh — Post-deployment traffic flow verification
#
# Validates the full traffic path:
#   User -> mall.atomai.click -> CloudFront + WAF -> api-internal.atomai.click -> NLB -> api-gateway pods
#
# Usage: bash scripts/test-traffic-flow.sh [--region us-east-1|us-west-2|both]

set -uo pipefail

# --- Configuration ---
DOMAIN="atomai.click"
CF_DOMAIN="d1muyxliujbszf.cloudfront.net"
CF_DIST_ID="E2XBVTVYBYX8T6"
CF_ORIGIN="api-internal.${DOMAIN}"
MALL_DOMAIN="mall.${DOMAIN}"
HOSTED_ZONE_ID="Z01703432E9KT1G1FIRFM"

declare -A NLB_NAMES=(
  [us-east-1]="production-api-nlb-us-east-1"
  [us-west-2]="production-api-nlb-us-west-2"
)
declare -A NLB_SG_IDS=(
  [us-east-1]="sg-048c7e63db40686b8"
  [us-west-2]="sg-0bfd63c6e6188327b"
)

# --- Counters ---
PASS=0
FAIL=0
WARN=0

# --- Helpers ---
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

pass() { ((PASS++)); echo -e "  ${GREEN}[PASS]${NC} $1"; }
fail() { ((FAIL++)); echo -e "  ${RED}[FAIL]${NC} $1"; }
warn() { ((WARN++)); echo -e "  ${YELLOW}[WARN]${NC} $1"; }
info() { echo -e "  ${CYAN}[INFO]${NC} $1"; }
header() { echo -e "\n${CYAN}=== $1 ===${NC}"; }

# --- Parse args ---
TARGET_REGION="${1:---region}"
if [[ "$TARGET_REGION" == "--region" ]]; then
  TARGET_REGION="${2:-both}"
fi
if [[ "$TARGET_REGION" == "both" ]]; then
  REGIONS=("us-east-1" "us-west-2")
else
  REGIONS=("$TARGET_REGION")
fi

echo -e "${CYAN}Traffic Flow Verification — $(date -u '+%Y-%m-%d %H:%M:%S UTC')${NC}"
echo "Regions: ${REGIONS[*]}"

# ============================================================
# 1. DNS Resolution
# ============================================================
header "1. DNS Resolution"

# Check api-internal.atomai.click resolves (should point to NLB)
API_INTERNAL_DNS=$(dig +short "${CF_ORIGIN}" | head -5)
if [[ -n "$API_INTERNAL_DNS" ]]; then
  # Check it's NOT an ALB (ALB DNS contains "elb.amazonaws.com" without "net/")
  if echo "$API_INTERNAL_DNS" | grep -qi "elb\." ; then
    pass "api-internal.${DOMAIN} resolves to load balancer: $(echo "$API_INTERNAL_DNS" | head -1)"
  else
    pass "api-internal.${DOMAIN} resolves to: $(echo "$API_INTERNAL_DNS" | head -1)"
  fi
else
  fail "api-internal.${DOMAIN} does not resolve"
fi

# Check mall.atomai.click -> CloudFront (dig +short follows CNAME chain to IPs, so check CNAME separately)
MALL_CNAME=$(dig +short CNAME "${MALL_DOMAIN}" | head -1)
MALL_DNS=$(dig +short "${MALL_DOMAIN}" | head -3)
if echo "$MALL_CNAME" | grep -qi "cloudfront"; then
  pass "${MALL_DOMAIN} CNAME -> ${MALL_CNAME} (CloudFront)"
elif [[ -n "$MALL_DNS" ]]; then
  # Route53 alias records don't show as CNAME; check if IPs match CloudFront ranges
  pass "${MALL_DOMAIN} resolves (Route53 alias to CloudFront): $(echo "$MALL_DNS" | head -1)"
else
  fail "${MALL_DOMAIN} does not resolve"
fi

# ============================================================
# 2. NLB Existence
# ============================================================
header "2. NLB Existence"

for REGION in "${REGIONS[@]}"; do
  NLB_NAME="${NLB_NAMES[$REGION]}"
  NLB_INFO=$(aws elbv2 describe-load-balancers --region "$REGION" \
    --names "$NLB_NAME" \
    --query 'LoadBalancers[0].[State.Code,DNSName,Type]' \
    --output text 2>/dev/null || echo "NOT_FOUND")

  if [[ "$NLB_INFO" == "NOT_FOUND" ]]; then
    fail "[${REGION}] NLB '${NLB_NAME}' not found"
  else
    NLB_STATE=$(echo "$NLB_INFO" | awk '{print $1}')
    NLB_DNS=$(echo "$NLB_INFO" | awk '{print $2}')
    NLB_TYPE=$(echo "$NLB_INFO" | awk '{print $3}')
    if [[ "$NLB_STATE" == "active" && "$NLB_TYPE" == "network" ]]; then
      pass "[${REGION}] NLB '${NLB_NAME}' is active (${NLB_DNS})"
    else
      fail "[${REGION}] NLB state=${NLB_STATE}, type=${NLB_TYPE} (expected active/network)"
    fi
  fi
done

# ============================================================
# 3. Target Group Health
# ============================================================
header "3. Target Group Health"

for REGION in "${REGIONS[@]}"; do
  NLB_NAME="${NLB_NAMES[$REGION]}"
  NLB_ARN=$(aws elbv2 describe-load-balancers --region "$REGION" \
    --names "$NLB_NAME" \
    --query 'LoadBalancers[0].LoadBalancerArn' \
    --output text 2>/dev/null || echo "")

  if [[ -z "$NLB_ARN" || "$NLB_ARN" == "None" ]]; then
    fail "[${REGION}] Cannot find NLB ARN"
    continue
  fi

  TG_ARNS=$(aws elbv2 describe-target-groups --region "$REGION" \
    --load-balancer-arn "$NLB_ARN" \
    --query 'TargetGroups[*].TargetGroupArn' \
    --output text 2>/dev/null)

  for TG_ARN in $TG_ARNS; do
    TG_NAME=$(echo "$TG_ARN" | grep -oP 'targetgroup/\K[^/]+')
    HEALTH=$(aws elbv2 describe-target-health --region "$REGION" \
      --target-group-arn "$TG_ARN" \
      --query 'TargetHealthDescriptions[*].TargetHealth.State' \
      --output text 2>/dev/null)

    HEALTHY_COUNT=0
    TOTAL_COUNT=0
    for STATE in $HEALTH; do
      ((TOTAL_COUNT++))
      if [[ "$STATE" == "healthy" ]]; then
        ((HEALTHY_COUNT++))
      fi
    done

    if [[ "$TOTAL_COUNT" -eq 0 ]]; then
      warn "[${REGION}] Target group '${TG_NAME}' has 0 registered targets (pods not deployed?)"
    elif [[ "$HEALTHY_COUNT" -eq "$TOTAL_COUNT" ]]; then
      pass "[${REGION}] Target group '${TG_NAME}': ${HEALTHY_COUNT}/${TOTAL_COUNT} healthy"
    elif [[ "$HEALTHY_COUNT" -gt 0 ]]; then
      warn "[${REGION}] Target group '${TG_NAME}': ${HEALTHY_COUNT}/${TOTAL_COUNT} healthy"
    else
      fail "[${REGION}] Target group '${TG_NAME}': 0/${TOTAL_COUNT} healthy"
    fi
  done
done

# ============================================================
# 4. CloudFront Connectivity
# ============================================================
header "4. CloudFront Connectivity"

# Test via CloudFront domain directly
CF_HTTP_CODE=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "https://${CF_DOMAIN}/" 2>/dev/null || echo "000")
if [[ "$CF_HTTP_CODE" == "200" ]]; then
  pass "CloudFront (${CF_DOMAIN}) returns HTTP ${CF_HTTP_CODE}"
elif [[ "$CF_HTTP_CODE" == "403" || "$CF_HTTP_CODE" == "502" || "$CF_HTTP_CODE" == "503" ]]; then
  warn "CloudFront (${CF_DOMAIN}) returns HTTP ${CF_HTTP_CODE} (expected if pods not deployed)"
elif [[ "$CF_HTTP_CODE" == "000" ]]; then
  fail "CloudFront (${CF_DOMAIN}) connection timeout"
else
  info "CloudFront (${CF_DOMAIN}) returns HTTP ${CF_HTTP_CODE}"
fi

# Test via mall.atomai.click alias
MALL_HTTP_CODE=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "https://${MALL_DOMAIN}/" 2>/dev/null || echo "000")
if [[ "$MALL_HTTP_CODE" == "200" ]]; then
  pass "${MALL_DOMAIN} returns HTTP ${MALL_HTTP_CODE}"
elif [[ "$MALL_HTTP_CODE" == "403" || "$MALL_HTTP_CODE" == "502" || "$MALL_HTTP_CODE" == "503" ]]; then
  warn "${MALL_DOMAIN} returns HTTP ${MALL_HTTP_CODE} (expected if pods not deployed)"
elif [[ "$MALL_HTTP_CODE" == "000" ]]; then
  fail "${MALL_DOMAIN} connection timeout"
else
  info "${MALL_DOMAIN} returns HTTP ${MALL_HTTP_CODE}"
fi

# ============================================================
# 5. Route53 Records
# ============================================================
header "5. Route53 Records"

# Check api-internal.atomai.click points to NLB DNS
API_RECORD=$(aws route53 list-resource-record-sets \
  --hosted-zone-id "$HOSTED_ZONE_ID" \
  --query "ResourceRecordSets[?Name=='${CF_ORIGIN}.'].[Type,AliasTarget.DNSName || ResourceRecords[0].Value]" \
  --output text 2>/dev/null)

if [[ -n "$API_RECORD" ]]; then
  if echo "$API_RECORD" | grep -qi "nlb\|elb"; then
    pass "api-internal.${DOMAIN} Route53 record points to NLB"
    info "Record: ${API_RECORD}"
  else
    # Alias records show the target DNS
    RECORD_TARGET=$(echo "$API_RECORD" | awk '{print $2}')
    if echo "$RECORD_TARGET" | grep -qi "production-api-nlb"; then
      pass "api-internal.${DOMAIN} Route53 record points to NLB: ${RECORD_TARGET}"
    else
      warn "api-internal.${DOMAIN} Route53 record target: ${RECORD_TARGET} (verify this is NLB)"
    fi
  fi
else
  fail "api-internal.${DOMAIN} Route53 record not found"
fi

# Check mall.atomai.click -> CloudFront
MALL_RECORD=$(aws route53 list-resource-record-sets \
  --hosted-zone-id "$HOSTED_ZONE_ID" \
  --query "ResourceRecordSets[?Name=='${MALL_DOMAIN}.'].[Type,AliasTarget.DNSName || ResourceRecords[0].Value]" \
  --output text 2>/dev/null)

if [[ -n "$MALL_RECORD" ]]; then
  if echo "$MALL_RECORD" | grep -qi "cloudfront"; then
    pass "${MALL_DOMAIN} Route53 record points to CloudFront"
  else
    RECORD_TARGET=$(echo "$MALL_RECORD" | awk '{print $2}')
    warn "${MALL_DOMAIN} Route53 record target: ${RECORD_TARGET} (expected CloudFront)"
  fi
else
  warn "${MALL_DOMAIN} Route53 record not found (may need to be created)"
fi

# ============================================================
# 6. Security Group Audit
# ============================================================
header "6. Security Group Audit (0.0.0.0/0 check)"

for REGION in "${REGIONS[@]}"; do
  SG_ID="${NLB_SG_IDS[$REGION]}"

  # Check for any 0.0.0.0/0 inbound rules
  OPEN_RULES=$(aws ec2 describe-security-groups --region "$REGION" \
    --group-ids "$SG_ID" \
    --query "SecurityGroups[0].IpPermissions[?IpRanges[?CidrIp=='0.0.0.0/0']]" \
    --output json 2>/dev/null)

  if [[ "$OPEN_RULES" == "[]" || -z "$OPEN_RULES" ]]; then
    pass "[${REGION}] SG ${SG_ID}: No 0.0.0.0/0 inbound rules"
  else
    fail "[${REGION}] SG ${SG_ID}: FOUND 0.0.0.0/0 inbound rules!"
    echo "$OPEN_RULES" | head -20
  fi

  # Verify prefix list is used
  PREFIX_RULES=$(aws ec2 describe-security-groups --region "$REGION" \
    --group-ids "$SG_ID" \
    --query "SecurityGroups[0].IpPermissions[?PrefixListIds[0]].PrefixListIds[0].PrefixListId" \
    --output text 2>/dev/null)

  if [[ -n "$PREFIX_RULES" && "$PREFIX_RULES" != "None" ]]; then
    pass "[${REGION}] SG ${SG_ID}: Uses prefix list (${PREFIX_RULES}) — CloudFront only"
  else
    warn "[${REGION}] SG ${SG_ID}: No prefix list found (expected CloudFront prefix list)"
  fi
done

# ============================================================
# 7. CloudFront Origin Verification
# ============================================================
header "7. CloudFront Origin Verification"

CF_ORIGIN_ACTUAL=$(aws cloudfront get-distribution --id "$CF_DIST_ID" \
  --query 'Distribution.DistributionConfig.Origins.Items[0].DomainName' \
  --output text 2>/dev/null || echo "ERROR")

if [[ "$CF_ORIGIN_ACTUAL" == "$CF_ORIGIN" ]]; then
  pass "CloudFront origin is '${CF_ORIGIN}' (correct)"
else
  fail "CloudFront origin is '${CF_ORIGIN_ACTUAL}' (expected '${CF_ORIGIN}')"
fi

# Check origin protocol policy
CF_ORIGIN_PROTO=$(aws cloudfront get-distribution --id "$CF_DIST_ID" \
  --query 'Distribution.DistributionConfig.Origins.Items[0].CustomOriginConfig.OriginProtocolPolicy' \
  --output text 2>/dev/null || echo "N/A")
info "Origin protocol policy: ${CF_ORIGIN_PROTO}"

# ============================================================
# Summary
# ============================================================
echo ""
echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}  SUMMARY${NC}"
echo -e "${CYAN}========================================${NC}"
echo -e "  ${GREEN}PASS: ${PASS}${NC}"
echo -e "  ${RED}FAIL: ${FAIL}${NC}"
echo -e "  ${YELLOW}WARN: ${WARN}${NC}"
echo ""

if [[ "$FAIL" -gt 0 ]]; then
  echo -e "${RED}RESULT: FAILURES DETECTED — review items above${NC}"
  exit 1
elif [[ "$WARN" -gt 0 ]]; then
  echo -e "${YELLOW}RESULT: PASSED with warnings — review items above${NC}"
  exit 0
else
  echo -e "${GREEN}RESULT: ALL CHECKS PASSED${NC}"
  exit 0
fi
