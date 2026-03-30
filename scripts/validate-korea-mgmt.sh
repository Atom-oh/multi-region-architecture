#!/bin/bash
# validate-korea-mgmt.sh — Validate Korea Management Cluster + NLB Weighted Routing
set +e  # Validation script — commands may fail for not-yet-deployed resources

REGION="ap-northeast-2"
NLB_NAME="prod-api-nlb-apne2"
MGMT_CLUSTER="mall-apne2-mgmt"
AZA_CLUSTER="mall-apne2-az-a"
AZC_CLUSTER="mall-apne2-az-c"
PASS=0; FAIL=0; WARN=0

green()  { echo -e "\033[32m[PASS]\033[0m $1"; ((PASS++)); }
red()    { echo -e "\033[31m[FAIL]\033[0m $1"; ((FAIL++)); }
yellow() { echo -e "\033[33m[WARN]\033[0m $1"; ((WARN++)); }
header() { echo -e "\n\033[1;36m═══ $1 ═══\033[0m"; }

# ─────────────────────────────────────────────────────────────────────────────
header "Phase 1: NLB Weighted Routing"
# ─────────────────────────────────────────────────────────────────────────────

echo "Checking NLB exists..."
NLB_INFO=$(aws elbv2 describe-load-balancers --names "$NLB_NAME" --region "$REGION" --output json 2>/dev/null || echo "NOTFOUND")
if [[ "$NLB_INFO" == "NOTFOUND" ]]; then
  red "NLB '$NLB_NAME' not found"
else
  NLB_ARN=$(echo "$NLB_INFO" | jq -r '.LoadBalancers[0].LoadBalancerArn')
  NLB_STATE=$(echo "$NLB_INFO" | jq -r '.LoadBalancers[0].State.Code')
  NLB_TYPE=$(echo "$NLB_INFO" | jq -r '.LoadBalancers[0].Type')
  NLB_AZS=$(echo "$NLB_INFO" | jq -r '.LoadBalancers[0].AvailabilityZones | length')

  if [[ "$NLB_STATE" == "active" ]]; then
    green "NLB '$NLB_NAME' is active (type: $NLB_TYPE)"
  else
    red "NLB state: $NLB_STATE (expected: active)"
  fi

  if [[ "$NLB_AZS" -ge 2 ]]; then
    green "NLB spans $NLB_AZS AZs (multi-AZ)"
  else
    red "NLB only in $NLB_AZS AZ (expected >= 2)"
  fi

  echo "Checking listeners..."
  LISTENERS=$(aws elbv2 describe-listeners --load-balancer-arn "$NLB_ARN" --region "$REGION" --output json 2>/dev/null)
  LISTENER_COUNT=$(echo "$LISTENERS" | jq '.Listeners | length')
  if [[ "$LISTENER_COUNT" -ge 1 ]]; then
    green "NLB has $LISTENER_COUNT listener(s)"
  else
    red "NLB has no listeners"
  fi

  echo "Checking target groups..."
  TGS=$(aws elbv2 describe-target-groups --load-balancer-arn "$NLB_ARN" --region "$REGION" --output json 2>/dev/null)
  TG_COUNT=$(echo "$TGS" | jq '.TargetGroups | length')
  if [[ "$TG_COUNT" -eq 2 ]]; then
    green "NLB has 2 target groups (weighted routing)"
  else
    red "NLB has $TG_COUNT target groups (expected 2)"
  fi

  echo "Checking listener rules for weighted forwarding..."
  for LISTENER_ARN in $(echo "$LISTENERS" | jq -r '.Listeners[].ListenerArn'); do
    RULES=$(aws elbv2 describe-rules --listener-arn "$LISTENER_ARN" --region "$REGION" --output json 2>/dev/null)
    FORWARD_TGS=$(echo "$RULES" | jq '[.Rules[].Actions[]? | select(.Type=="forward") | .ForwardConfig.TargetGroups[]?] | length')
    if [[ "$FORWARD_TGS" -ge 2 ]]; then
      green "Listener has weighted forward to $FORWARD_TGS target groups"
    else
      yellow "Listener forward config: $FORWARD_TGS target groups"
    fi
  done

  echo "Checking target group health..."
  for TG_ARN in $(echo "$TGS" | jq -r '.TargetGroups[].TargetGroupArn'); do
    TG_NAME=$(echo "$TGS" | jq -r ".TargetGroups[] | select(.TargetGroupArn==\"$TG_ARN\") | .TargetGroupName")
    HEALTH=$(aws elbv2 describe-target-health --target-group-arn "$TG_ARN" --region "$REGION" --output json 2>/dev/null)
    HEALTHY=$(echo "$HEALTH" | jq '[.TargetHealthDescriptions[]? | select(.TargetHealth.State=="healthy")] | length')
    TOTAL=$(echo "$HEALTH" | jq '.TargetHealthDescriptions | length')
    if [[ "$TOTAL" -eq 0 ]]; then
      yellow "TG '$TG_NAME': no targets registered (pods may not be deployed yet)"
    elif [[ "$HEALTHY" -gt 0 ]]; then
      green "TG '$TG_NAME': $HEALTHY/$TOTAL targets healthy"
    else
      red "TG '$TG_NAME': 0/$TOTAL targets healthy"
    fi
  done
fi

# ─────────────────────────────────────────────────────────────────────────────
header "Phase 2: EKS Management Cluster"
# ─────────────────────────────────────────────────────────────────────────────

echo "Checking EKS cluster exists..."
CLUSTER_INFO=$(aws eks describe-cluster --name "$MGMT_CLUSTER" --region "$REGION" --output json 2>/dev/null || echo "NOTFOUND")
if [[ "$CLUSTER_INFO" == "NOTFOUND" ]]; then
  red "EKS cluster '$MGMT_CLUSTER' not found"
else
  CLUSTER_STATUS=$(echo "$CLUSTER_INFO" | jq -r '.cluster.status')
  CLUSTER_VERSION=$(echo "$CLUSTER_INFO" | jq -r '.cluster.version')
  CLUSTER_ENDPOINT=$(echo "$CLUSTER_INFO" | jq -r '.cluster.endpoint')

  if [[ "$CLUSTER_STATUS" == "ACTIVE" ]]; then
    green "EKS cluster '$MGMT_CLUSTER' is ACTIVE (v$CLUSTER_VERSION)"
  else
    red "EKS cluster status: $CLUSTER_STATUS (expected: ACTIVE)"
  fi

  echo "Updating kubeconfig..."
  aws eks update-kubeconfig --name "$MGMT_CLUSTER" --region "$REGION" --alias "$MGMT_CLUSTER" 2>/dev/null
  if kubectl get nodes --context "$MGMT_CLUSTER" --no-headers 2>/dev/null | grep -q "Ready"; then
    NODE_COUNT=$(kubectl get nodes --context "$MGMT_CLUSTER" --no-headers 2>/dev/null | grep -c "Ready" || true)
    green "Management cluster has $NODE_COUNT Ready node(s)"
  else
    red "No Ready nodes in management cluster"
  fi

  echo "Checking node groups..."
  NGS=$(aws eks list-nodegroups --cluster-name "$MGMT_CLUSTER" --region "$REGION" --output json 2>/dev/null)
  NG_COUNT=$(echo "$NGS" | jq '.nodegroups | length')
  if [[ "$NG_COUNT" -ge 1 ]]; then
    green "Management cluster has $NG_COUNT node group(s)"
    for NG in $(echo "$NGS" | jq -r '.nodegroups[]'); do
      NG_INFO=$(aws eks describe-nodegroup --cluster-name "$MGMT_CLUSTER" --nodegroup-name "$NG" --region "$REGION" --output json 2>/dev/null)
      NG_STATUS=$(echo "$NG_INFO" | jq -r '.nodegroup.status')
      NG_DESIRED=$(echo "$NG_INFO" | jq -r '.nodegroup.scalingConfig.desiredSize')
      echo "  Node group '$NG': status=$NG_STATUS, desired=$NG_DESIRED"
    done
  else
    red "No node groups found"
  fi
fi

# ─────────────────────────────────────────────────────────────────────────────
header "Phase 3: Management Cluster IRSA Roles"
# ─────────────────────────────────────────────────────────────────────────────

IRSA_ROLES=(
  "production-otel-collector-ap-northeast-2-mgmt"
  "production-tempo-ap-northeast-2-mgmt"
  "mall-apne2-mgmt-alb-controller-apne2-mgmt"
  "mall-apne2-mgmt-karpenter-controller-apne2-mgmt"
)
for ROLE_NAME in "${IRSA_ROLES[@]}"; do
  if aws iam get-role --role-name "$ROLE_NAME" --output json 2>/dev/null | jq -r '.Role.RoleName' | grep -q "$ROLE_NAME"; then
    green "IAM role '$ROLE_NAME' exists"
  else
    yellow "IAM role '$ROLE_NAME' not found (may be created by eks-mgmt apply)"
  fi
done

# ─────────────────────────────────────────────────────────────────────────────
header "Phase 4: Tempo S3 Bucket"
# ─────────────────────────────────────────────────────────────────────────────

TEMPO_BUCKET="production-mall-tempo-traces-ap-northeast-2-mgmt"
if aws s3api head-bucket --bucket "$TEMPO_BUCKET" --region "$REGION" 2>/dev/null; then
  green "Tempo S3 bucket '$TEMPO_BUCKET' exists"
else
  yellow "Tempo S3 bucket '$TEMPO_BUCKET' not found (may be created by eks-mgmt apply)"
fi

# ─────────────────────────────────────────────────────────────────────────────
header "Phase 5: Internal NLBs (Management Cluster)"
# ─────────────────────────────────────────────────────────────────────────────

if [[ "$CLUSTER_INFO" != "NOTFOUND" ]] && kubectl get svc --context "$MGMT_CLUSTER" -A --no-headers 2>/dev/null | grep -q "LoadBalancer"; then
  echo "Checking internal NLB services..."
  for SVC_NS_NAME in "observability/clickhouse-nlb" "observability/tempo-nlb" "monitoring/prometheus-nlb"; do
    NS=$(echo "$SVC_NS_NAME" | cut -d/ -f1)
    SVC=$(echo "$SVC_NS_NAME" | cut -d/ -f2)
    SVC_INFO=$(kubectl get svc "$SVC" -n "$NS" --context "$MGMT_CLUSTER" -o json 2>/dev/null || echo "NOTFOUND")
    if [[ "$SVC_INFO" == "NOTFOUND" ]]; then
      yellow "Service '$SVC_NS_NAME' not deployed yet"
    else
      LB_HOST=$(echo "$SVC_INFO" | jq -r '.status.loadBalancer.ingress[0].hostname // "pending"')
      if [[ "$LB_HOST" != "pending" && "$LB_HOST" != "null" ]]; then
        green "Internal NLB '$SVC': $LB_HOST"
      else
        yellow "Service '$SVC' exists but LB not provisioned yet"
      fi
    fi
  done
else
  yellow "Skipping internal NLB checks (management cluster not ready or no LB services)"
fi

# ─────────────────────────────────────────────────────────────────────────────
header "Phase 6: ArgoCD on Management Cluster"
# ─────────────────────────────────────────────────────────────────────────────

if [[ "$CLUSTER_INFO" != "NOTFOUND" ]]; then
  ARGOCD_PODS=$(kubectl get pods -n argocd --context "$MGMT_CLUSTER" --no-headers 2>/dev/null | grep -c "Running" || true)
  if [[ "$ARGOCD_PODS" -gt 0 ]]; then
    green "ArgoCD: $ARGOCD_PODS pods running on management cluster"
  else
    yellow "ArgoCD not yet deployed on management cluster"
  fi
fi

# ─────────────────────────────────────────────────────────────────────────────
header "Phase 7: Observability Stack on Management Cluster"
# ─────────────────────────────────────────────────────────────────────────────

if [[ "$CLUSTER_INFO" != "NOTFOUND" ]]; then
  for NS_LABEL in "observability/clickhouse" "observability/tempo" "monitoring/prometheus" "monitoring/grafana"; do
    NS=$(echo "$NS_LABEL" | cut -d/ -f1)
    LABEL=$(echo "$NS_LABEL" | cut -d/ -f2)
    POD_COUNT=$(kubectl get pods -n "$NS" --context "$MGMT_CLUSTER" --no-headers 2>/dev/null | grep "$LABEL" | grep -c "Running" || true)
    if [[ "$POD_COUNT" -gt 0 ]]; then
      green "$LABEL: $POD_COUNT pod(s) running in $NS"
    else
      yellow "$LABEL: not yet running in $NS (needs ArgoCD sync)"
    fi
  done
fi

# ─────────────────────────────────────────────────────────────────────────────
header "Phase 8: Workload Clusters Status"
# ─────────────────────────────────────────────────────────────────────────────

for CLUSTER in "$AZA_CLUSTER" "$AZC_CLUSTER"; do
  echo "Checking $CLUSTER..."
  if kubectl get nodes --context "$CLUSTER" --no-headers 2>/dev/null | grep -q "Ready"; then
    NODE_COUNT=$(kubectl get nodes --context "$CLUSTER" --no-headers 2>/dev/null | grep -c "Ready" || true)
    POD_COUNT=$(kubectl get pods -A --context "$CLUSTER" --no-headers 2>/dev/null | grep -c "Running" || true)
    green "$CLUSTER: $NODE_COUNT nodes, $POD_COUNT running pods"
  else
    yellow "$CLUSTER: cannot reach (kubeconfig may not be set)"
  fi
done

# ─────────────────────────────────────────────────────────────────────────────
header "Phase 9: Route53 DNS Records"
# ─────────────────────────────────────────────────────────────────────────────

echo "Checking for mgmt.internal.atomai.click hosted zone..."
HZ_ID=$(aws route53 list-hosted-zones --output json 2>/dev/null | jq -r '.HostedZones[] | select(.Name | contains("mgmt.internal.atomai.click")) | .Id' | head -1)
if [[ -n "$HZ_ID" ]]; then
  green "Private hosted zone found: $HZ_ID"
  for RECORD in "clickhouse.mgmt.internal.atomai.click" "tempo.mgmt.internal.atomai.click" "prometheus.mgmt.internal.atomai.click"; do
    RR=$(aws route53 list-resource-record-sets --hosted-zone-id "$HZ_ID" --output json 2>/dev/null | jq -r ".ResourceRecordSets[] | select(.Name==\"${RECORD}.\") | .Type")
    if [[ -n "$RR" ]]; then
      green "DNS record: $RECORD ($RR)"
    else
      yellow "DNS record '$RECORD' not found yet"
    fi
  done
else
  yellow "Private hosted zone 'mgmt.internal.atomai.click' not found (needs creation)"
fi

# ─────────────────────────────────────────────────────────────────────────────
header "Summary"
# ─────────────────────────────────────────────────────────────────────────────

echo ""
echo -e "  \033[32mPASS: $PASS\033[0m  |  \033[31mFAIL: $FAIL\033[0m  |  \033[33mWARN: $WARN\033[0m"
echo ""

if [[ $FAIL -gt 0 ]]; then
  echo -e "\033[31mValidation found $FAIL failure(s). Please investigate.\033[0m"
  exit 1
elif [[ $WARN -gt 0 ]]; then
  echo -e "\033[33mValidation passed with $WARN warning(s). Some resources may still be provisioning.\033[0m"
  exit 0
else
  echo -e "\033[32mAll checks passed!\033[0m"
  exit 0
fi
