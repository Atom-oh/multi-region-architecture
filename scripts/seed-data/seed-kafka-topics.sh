#!/bin/bash
# ============================================================================
# Multi-Region Shopping Mall - MSK (Kafka) Topic Creation
# Creates event topics for all 20 microservices
# ============================================================================

set -euo pipefail

BOOTSTRAP="${MSK_BOOTSTRAP:-localhost:9092}"
KAFKA_BIN="${KAFKA_HOME:-/opt/kafka}/bin"
REPLICATION=3
RETENTION_MS=604800000  # 7 days

echo "=== MSK Topic Creation ==="
echo "Bootstrap: ${BOOTSTRAP}"

create_topic() {
  local name=$1
  local partitions=$2
  local retention=${3:-$RETENTION_MS}
  local cleanup=${4:-delete}

  echo -n "  Creating ${name} (partitions=${partitions})... "
  ${KAFKA_BIN}/kafka-topics.sh --bootstrap-server "${BOOTSTRAP}" \
    --create --if-not-exists \
    --topic "${name}" \
    --partitions "${partitions}" \
    --replication-factor ${REPLICATION} \
    --config retention.ms="${retention}" \
    --config cleanup.policy="${cleanup}" \
    2>/dev/null && echo "OK" || echo "EXISTS"
}

# ── Order Events ────────────────────────────────────────────────────────────
echo ""
echo "Order Domain:"
create_topic "order.created"       12
create_topic "order.confirmed"     12
create_topic "order.cancelled"     6
create_topic "order.status-changed" 12

# ── Payment Events ──────────────────────────────────────────────────────────
echo ""
echo "Payment Domain:"
create_topic "payment.initiated"   12
create_topic "payment.completed"   12
create_topic "payment.failed"      6
create_topic "payment.refunded"    6

# ── Inventory Events ────────────────────────────────────────────────────────
echo ""
echo "Inventory Domain:"
create_topic "inventory.reserved"    12
create_topic "inventory.released"    6
create_topic "inventory.low-stock"   3
create_topic "inventory.restocked"   6

# ── Shipping/Fulfillment Events ─────────────────────────────────────────────
echo ""
echo "Shipping Domain:"
create_topic "shipping.dispatched"   12
create_topic "shipping.in-transit"   12
create_topic "shipping.delivered"    12
create_topic "shipping.returned"     6

# ── Notification Events ─────────────────────────────────────────────────────
echo ""
echo "Notification Domain:"
create_topic "notification.email"    6
create_topic "notification.push"     6
create_topic "notification.sms"      3
create_topic "notification.kakao"    6

# ── User Events ─────────────────────────────────────────────────────────────
echo ""
echo "User Domain:"
create_topic "user.registered"     6
create_topic "user.profile-updated" 6
create_topic "user.login"          6

# ── Product/Catalog Events ──────────────────────────────────────────────────
echo ""
echo "Product Domain:"
create_topic "product.created"      6
create_topic "product.updated"      6
create_topic "product.price-changed" 6
create_topic "product.viewed"       12

# ── Review Events ───────────────────────────────────────────────────────────
echo ""
echo "Review Domain:"
create_topic "review.submitted"    6
create_topic "review.approved"     6

# ── Search Events (analytics) ──────────────────────────────────────────────
echo ""
echo "Search/Analytics Domain:"
create_topic "search.query-logged"  12
create_topic "analytics.page-view"  12
create_topic "analytics.click"      12

# ── Dead Letter Queue ───────────────────────────────────────────────────────
echo ""
echo "Infrastructure:"
create_topic "dlq.all"              6  2592000000  # 30 days retention
create_topic "saga.orchestrator"    12

# ── List all topics ─────────────────────────────────────────────────────────
echo ""
echo "=== All Topics ==="
${KAFKA_BIN}/kafka-topics.sh --bootstrap-server "${BOOTSTRAP}" --list 2>/dev/null | sort || echo "(could not list topics)"

TOPIC_COUNT=$(${KAFKA_BIN}/kafka-topics.sh --bootstrap-server "${BOOTSTRAP}" --list 2>/dev/null | wc -l || echo "?")
echo ""
echo "MSK seed complete: ${TOPIC_COUNT} topics created"
