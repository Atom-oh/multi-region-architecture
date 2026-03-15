#!/bin/bash
# ============================================================================
# Multi-Region Shopping Mall - ElastiCache (Valkey/Redis) Seed Data
# Caches: sessions, product cache, cart, rate limiting, leaderboards
# ============================================================================

set -euo pipefail

REDIS_HOST="${ELASTICACHE_ENDPOINT:-localhost}"
REDIS_PORT="${ELASTICACHE_PORT:-6379}"
REDIS_CLI="redis-cli -h ${REDIS_HOST} -p ${REDIS_PORT} --tls --no-auth-warning"

echo "=== ElastiCache (Valkey) Seed Data ==="
echo "Endpoint: ${REDIS_HOST}:${REDIS_PORT}"

# ── Product Cache (top 30 products) ─────────────────────────────────────────
echo ""
echo "Seeding product cache..."
for i in $(seq 1 30); do
  pid="PROD-$(printf '%03d' $i)"
  price=$(( RANDOM % 1990000 + 10000 ))
  stock=$(( RANDOM % 500 + 5 ))
  $REDIS_CLI SET "product:${pid}" "{\"productId\":\"${pid}\",\"price\":${price},\"stock\":${stock},\"cached_at\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}" EX 3600 > /dev/null 2>&1
done
echo "  Cached 30 products (TTL: 1h)"

# ── Category Cache ──────────────────────────────────────────────────────────
echo "Seeding category cache..."
CATEGORIES='[{"id":"CAT-01","name":"전자제품","slug":"electronics"},{"id":"CAT-02","name":"패션","slug":"fashion"},{"id":"CAT-03","name":"식품","slug":"food"},{"id":"CAT-04","name":"뷰티","slug":"beauty"},{"id":"CAT-05","name":"가전","slug":"appliances"},{"id":"CAT-06","name":"스포츠","slug":"sports"},{"id":"CAT-07","name":"도서","slug":"books"},{"id":"CAT-08","name":"반려동물","slug":"pets"},{"id":"CAT-09","name":"가구","slug":"furniture"},{"id":"CAT-10","name":"유아용품","slug":"baby"}]'
$REDIS_CLI SET "cache:categories" "$CATEGORIES" EX 86400 > /dev/null 2>&1
echo "  Cached 10 categories (TTL: 24h)"

# ── Shopping Carts (20 active carts) ────────────────────────────────────────
echo "Seeding shopping carts..."
for i in $(seq 1 20); do
  uid="a0000001-0000-0000-0000-$(printf '%012d' $i)"
  item_count=$(( RANDOM % 5 + 1 ))
  cart_items=""
  for j in $(seq 1 $item_count); do
    pid="PROD-$(printf '%03d' $(( RANDOM % 150 + 1 )))"
    qty=$(( RANDOM % 3 + 1 ))
    price=$(( RANDOM % 500000 + 10000 ))
    if [ -n "$cart_items" ]; then cart_items="${cart_items},"; fi
    cart_items="${cart_items}{\"productId\":\"${pid}\",\"quantity\":${qty},\"price\":${price}}"
  done
  $REDIS_CLI SET "cart:${uid}" "{\"userId\":\"${uid}\",\"items\":[${cart_items}],\"updatedAt\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}" EX 604800 > /dev/null 2>&1
done
echo "  Created 20 carts (TTL: 7d)"

# ── User Sessions (30 active sessions) ─────────────────────────────────────
echo "Seeding user sessions..."
for i in $(seq 1 30); do
  uid="a0000001-0000-0000-0000-$(printf '%012d' $i)"
  session_id="sess_$(openssl rand -hex 16 2>/dev/null || echo "$(date +%s)${i}")"
  tiers=("bronze" "silver" "gold" "platinum" "diamond")
  tier=${tiers[$(( i % 5 ))]}
  $REDIS_CLI SET "session:${session_id}" "{\"userId\":\"${uid}\",\"tier\":\"${tier}\",\"loginAt\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"ip\":\"10.0.$(( RANDOM % 255 )).$(( RANDOM % 255 ))\"}" EX 7200 > /dev/null 2>&1
  $REDIS_CLI SET "user-session:${uid}" "${session_id}" EX 7200 > /dev/null 2>&1
done
echo "  Created 30 sessions (TTL: 2h)"

# ── Rate Limiting Counters ──────────────────────────────────────────────────
echo "Seeding rate limit counters..."
for i in $(seq 1 10); do
  uid="a0000001-0000-0000-0000-$(printf '%012d' $i)"
  $REDIS_CLI SET "ratelimit:api:${uid}" "$(( RANDOM % 50 ))" EX 60 > /dev/null 2>&1
  $REDIS_CLI SET "ratelimit:search:${uid}" "$(( RANDOM % 20 ))" EX 60 > /dev/null 2>&1
done
echo "  Set 20 rate limit counters (TTL: 60s)"

# ── Popular Products Sorted Set (leaderboard) ──────────────────────────────
echo "Seeding popularity leaderboard..."
for i in $(seq 1 50); do
  pid="PROD-$(printf '%03d' $i)"
  score=$(( RANDOM % 10000 + 100 ))
  $REDIS_CLI ZADD "leaderboard:popular" "$score" "$pid" > /dev/null 2>&1
done
echo "  Added 50 products to popularity leaderboard"

# ── Real-time Inventory Counts ──────────────────────────────────────────────
echo "Seeding inventory counters..."
for i in $(seq 1 150); do
  pid="PROD-$(printf '%03d' $i)"
  stock=$(( RANDOM % 500 + 5 ))
  $REDIS_CLI SET "stock:${pid}" "$stock" > /dev/null 2>&1
done
echo "  Set 150 inventory counters"

# ── Recent Search Queries (per user) ────────────────────────────────────────
echo "Seeding recent search history..."
SEARCHES=("삼성 갤럭시" "아이폰" "나이키 운동화" "냉장고" "에어팟" "김치" "소파" "청소기" "원피스" "화장품" "노트북" "커피머신" "캠핑용품" "강아지 사료" "아기 기저귀")
for i in $(seq 1 20); do
  uid="a0000001-0000-0000-0000-$(printf '%012d' $i)"
  for j in $(seq 1 5); do
    query=${SEARCHES[$(( RANDOM % ${#SEARCHES[@]} ))]}
    $REDIS_CLI LPUSH "search-history:${uid}" "$query" > /dev/null 2>&1
  done
  $REDIS_CLI LTRIM "search-history:${uid}" 0 9 > /dev/null 2>&1
  $REDIS_CLI EXPIRE "search-history:${uid}" 2592000 > /dev/null 2>&1
done
echo "  Added search history for 20 users (TTL: 30d)"

# ── Flash Sale / Promotion Cache ────────────────────────────────────────────
echo "Seeding promotion cache..."
$REDIS_CLI SET "promo:flash-sale" "{\"id\":\"FLASH-001\",\"title\":\"오늘만 특가! 전자제품 최대 50% 할인\",\"startAt\":\"$(date -u +%Y-%m-%dT00:00:00Z)\",\"endAt\":\"$(date -u +%Y-%m-%dT23:59:59Z)\",\"products\":[\"PROD-001\",\"PROD-005\",\"PROD-010\",\"PROD-015\"],\"discountRate\":50}" EX 86400 > /dev/null 2>&1
$REDIS_CLI SET "promo:weekend-coupon" "{\"id\":\"COUPON-001\",\"title\":\"주말 쿠폰 10% 할인\",\"code\":\"WEEKEND10\",\"discountRate\":10,\"minOrderAmount\":30000,\"maxDiscount\":50000}" EX 172800 > /dev/null 2>&1
echo "  Cached 2 promotions"

# ── Verification ────────────────────────────────────────────────────────────
echo ""
echo "=== Verification ==="
echo -n "Total keys: "
$REDIS_CLI DBSIZE 2>/dev/null | awk '{print $NF}' || echo "?"

echo -n "Top 5 popular products: "
$REDIS_CLI ZREVRANGE "leaderboard:popular" 0 4 2>/dev/null | tr '\n' ' ' || echo "?"
echo ""

echo -n "Sample cart: "
$REDIS_CLI GET "cart:a0000001-0000-0000-0000-000000000001" 2>/dev/null | head -c 100 || echo "?"
echo "..."

echo ""
echo "ElastiCache seed complete!"
