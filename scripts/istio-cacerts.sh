#!/bin/bash
# istio-cacerts.sh — Shared root of trust for the Korea ambient multicluster mesh.
#
# Without this, each cluster's istiod self-signs its own CA: remote-secret
# endpoint discovery still works, but cross-cluster HBONE mTLS handshakes are
# untrusted and zone failover NEVER actually works. Run ONCE, BEFORE istiod
# is installed (or restart istiod afterwards).
#
#   bash scripts/istio-cacerts.sh
#
# Generates a root CA + one intermediate per cluster (openssl only, no istio
# checkout needed) and creates the `cacerts` secret in istio-system on both
# workload clusters. Root key material stays in WORK_DIR — store it in
# Secrets Manager and delete the local copy after running:
#   aws secretsmanager create-secret --name mall/istio/root-ca \
#     --secret-string file://<WORK_DIR>/root-key.pem
set -euo pipefail

CLUSTERS=(mall-apne2-az-a mall-apne2-az-c)
WORK_DIR="${WORK_DIR:-$(mktemp -d)}"
DAYS_ROOT=3650
DAYS_INTERMEDIATE=1825

cd "$WORK_DIR"
echo "Working in: $WORK_DIR"

# ── Root CA ──────────────────────────────────────────────────────────────────
if [ ! -f root-key.pem ]; then
  openssl genrsa -out root-key.pem 4096
  openssl req -x509 -new -key root-key.pem -days "$DAYS_ROOT" -sha256 \
    -subj "/O=vellure-mesh-kr/CN=Root CA" \
    -addext "basicConstraints=critical,CA:true" \
    -addext "keyUsage=critical,keyCertSign,cRLSign" \
    -out root-cert.pem
  echo "✓ Root CA generated"
fi

# ── Per-cluster intermediate + cacerts secret ────────────────────────────────
for cluster in "${CLUSTERS[@]}"; do
  mkdir -p "$cluster"
  openssl genrsa -out "$cluster/ca-key.pem" 4096
  openssl req -new -key "$cluster/ca-key.pem" \
    -subj "/O=vellure-mesh-kr/CN=${cluster} Intermediate CA" \
    -out "$cluster/ca.csr"
  openssl x509 -req -in "$cluster/ca.csr" \
    -CA root-cert.pem -CAkey root-key.pem -CAcreateserial \
    -days "$DAYS_INTERMEDIATE" -sha256 \
    -extfile <(printf "basicConstraints=critical,CA:true,pathlen:0\nkeyUsage=critical,keyCertSign,cRLSign\nsubjectAltName=URI:spiffe://cluster.local/ns/istio-system/sa/istiod-service-account") \
    -out "$cluster/ca-cert.pem"
  cat "$cluster/ca-cert.pem" root-cert.pem > "$cluster/cert-chain.pem"

  kubectl create namespace istio-system --context "$cluster" \
    --dry-run=client -o yaml | kubectl apply -f - --context "$cluster"
  kubectl create secret generic cacerts -n istio-system --context "$cluster" \
    --from-file=ca-cert.pem="$cluster/ca-cert.pem" \
    --from-file=ca-key.pem="$cluster/ca-key.pem" \
    --from-file=root-cert.pem=root-cert.pem \
    --from-file=cert-chain.pem="$cluster/cert-chain.pem" \
    --dry-run=client -o yaml | kubectl apply -f - --context "$cluster"
  echo "✓ cacerts created on $cluster"
done

echo ""
echo "Done. If istiod was already running, restart it to pick up the CA:"
for cluster in "${CLUSTERS[@]}"; do
  echo "  kubectl rollout restart deployment/istiod -n istio-system --context $cluster"
done
echo ""
echo "Root key material is in $WORK_DIR — store root-key.pem in Secrets Manager"
echo "and delete the local copy."
