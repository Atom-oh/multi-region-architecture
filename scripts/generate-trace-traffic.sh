#!/usr/bin/env bash
# generate-trace-traffic.sh — Generate multi-hop API calls and verify multi-span traces in Tempo.
# Usage: ./scripts/generate-trace-traffic.sh [BASE_URL]
#   BASE_URL defaults to the api-gateway K8s service (requires kubectl port-forward or in-cluster access).
#   For external access: ./scripts/generate-trace-traffic.sh https://mall.atomai.click

set -euo pipefail

BASE_URL="${1:-http://localhost:8080}"
REPEAT="${REPEAT:-20}"
TEMPO_URL="${TEMPO_URL:-http://localhost:3200}"
PASS=0
FAIL=0

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

log()  { echo -e "${GREEN}[OK]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
err()  { echo -e "${RED}[FAIL]${NC} $*"; }

# ─────────────────────────────────────────────
# Scenario 1: Browse products (api-gw → product-catalog)
# ─────────────────────────────────────────────
echo ""
echo "=== Scenario 1: GET /api/v1/products/ (api-gw → product-catalog) ==="
for i in $(seq 1 "$REPEAT"); do
  code=$(curl -s -o /dev/null -w '%{http_code}' "${BASE_URL}/api/v1/products/" 2>/dev/null || echo "000")
  if [[ "$code" =~ ^(200|404)$ ]]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    [[ "$i" -le 3 ]] && warn "Request $i returned HTTP $code"
  fi
done
log "Scenario 1 complete: $REPEAT requests sent"

# ─────────────────────────────────────────────
# Scenario 2: Search products (api-gw → search → product-catalog)
# ─────────────────────────────────────────────
echo ""
echo "=== Scenario 2: GET /api/v1/search/?q=galaxy (api-gw → search → product-catalog) ==="
for i in $(seq 1 "$REPEAT"); do
  code=$(curl -s -o /dev/null -w '%{http_code}' "${BASE_URL}/api/v1/search/?q=galaxy" 2>/dev/null || echo "000")
  if [[ "$code" =~ ^(200|404)$ ]]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    [[ "$i" -le 3 ]] && warn "Request $i returned HTTP $code"
  fi
done
log "Scenario 2 complete: $REPEAT requests sent"

# ─────────────────────────────────────────────
# Scenario 3: Create order (api-gw → order → inventory + payment + shipping)
# ─────────────────────────────────────────────
echo ""
echo "=== Scenario 3: POST /api/v1/orders/ (api-gw → order → inventory + payment + shipping) ==="
ORDER_BODY='{"userId":"USR-001","items":[{"productId":"PRD-001","quantity":1,"price":1890000}],"shippingAddress":{"city":"Seoul","district":"Gangnam","zipCode":"06000"}}'
for i in $(seq 1 "$REPEAT"); do
  code=$(curl -s -o /dev/null -w '%{http_code}' -X POST \
    -H "Content-Type: application/json" \
    -d "$ORDER_BODY" \
    "${BASE_URL}/api/v1/orders/" 2>/dev/null || echo "000")
  if [[ "$code" =~ ^(200|201|404|500)$ ]]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    [[ "$i" -le 3 ]] && warn "Request $i returned HTTP $code"
  fi
done
log "Scenario 3 complete: $REPEAT requests sent"

# ─────────────────────────────────────────────
# Scenario 4: Get recommendations (api-gw → recommendation)
# ─────────────────────────────────────────────
echo ""
echo "=== Scenario 4: GET /api/v1/recommendations/ (api-gw → recommendation) ==="
for i in $(seq 1 "$REPEAT"); do
  code=$(curl -s -o /dev/null -w '%{http_code}' "${BASE_URL}/api/v1/recommendations/" 2>/dev/null || echo "000")
  if [[ "$code" =~ ^(200|404)$ ]]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    [[ "$i" -le 3 ]] && warn "Request $i returned HTTP $code"
  fi
done
log "Scenario 4 complete: $REPEAT requests sent"

# ─────────────────────────────────────────────
# Summary
# ─────────────────────────────────────────────
TOTAL=$((PASS + FAIL))
echo ""
echo "=== Traffic Generation Summary ==="
echo "  Total requests: $TOTAL"
echo "  Success: $PASS"
echo "  Failed:  $FAIL"

# ─────────────────────────────────────────────
# Tempo verification (optional — requires Tempo access)
# ─────────────────────────────────────────────
echo ""
echo "=== Tempo Trace Verification ==="
echo "Waiting 15s for spans to flush (BatchSpanProcessor 5s + Tempo ingest)..."
sleep 15

verify_traces() {
  local service_name="$1"
  local label="$2"

  local response
  response=$(curl -sf "${TEMPO_URL}/api/search?tags=service.name%3D${service_name}&limit=5" 2>/dev/null) || {
    warn "Cannot reach Tempo at ${TEMPO_URL} — skipping verification for ${label}"
    return
  }

  local trace_count
  trace_count=$(echo "$response" | python3 -c "import sys,json; d=json.load(sys.stdin); print(len(d.get('traces',[])))" 2>/dev/null || echo "0")

  if [[ "$trace_count" -eq 0 ]]; then
    warn "No traces found for ${service_name}"
    return
  fi

  # Check the first trace for multi-span
  local trace_id
  trace_id=$(echo "$response" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['traces'][0]['traceID'])" 2>/dev/null)

  local trace_detail
  trace_detail=$(curl -sf "${TEMPO_URL}/api/traces/${trace_id}" 2>/dev/null) || {
    warn "Cannot fetch trace detail for ${trace_id}"
    return
  }

  local span_count service_names
  span_count=$(echo "$trace_detail" | python3 -c "
import sys, json
d = json.load(sys.stdin)
spans = []
for batch in d.get('batches', []):
    for ss in batch.get('scopeSpans', batch.get('instrumentationLibrarySpans', [])):
        spans.extend(ss.get('spans', []))
print(len(spans))
" 2>/dev/null || echo "0")

  service_names=$(echo "$trace_detail" | python3 -c "
import sys, json
d = json.load(sys.stdin)
names = set()
for batch in d.get('batches', []):
    res = batch.get('resource', {})
    for attr in res.get('attributes', []):
        if attr.get('key') == 'service.name':
            val = attr.get('value', {})
            names.add(val.get('stringValue', val.get('Value', {}).get('StringValue', '')))
print(', '.join(sorted(names)) if names else 'unknown')
" 2>/dev/null || echo "unknown")

  if [[ "$span_count" -ge 2 ]]; then
    log "${label}: traceID=${trace_id} has ${span_count} spans across services: [${service_names}]"
  else
    warn "${label}: traceID=${trace_id} has only ${span_count} span(s) — propagation may still be broken"
    warn "  Services: [${service_names}]"
  fi
}

verify_traces "api-gateway" "API Gateway traces"
verify_traces "order-service" "Order Service traces"
verify_traces "search-service" "Search Service traces"

echo ""
echo "=== Done ==="
echo "To inspect traces manually:"
echo "  kubectl port-forward -n observability svc/grafana 3000:3000"
echo "  Open http://localhost:3000 → Explore → Tempo → Search by service.name"
