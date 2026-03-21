"""Synthetic monitor — E2E user journey traffic generator for multi-region shopping mall."""

import json
import logging
import os
import time
import uuid

import requests
from opentelemetry import trace
from opentelemetry.sdk.resources import Resource
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from opentelemetry.trace.propagation.tracecontext import TraceContextTextMapPropagator

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
BASE_URL = os.getenv("BASE_URL", "https://mall.atomai.click")
OTEL_ENDPOINT = os.getenv("OTEL_EXPORTER_OTLP_ENDPOINT", "http://otel-collector.platform.svc.cluster.local:4317")
ORIGIN_REGION = os.getenv("ORIGIN_REGION", "unknown")
ORIGIN_LABEL = "test-east" if "east" in ORIGIN_REGION else "test-west" if "west" in ORIGIN_REGION else f"test-{ORIGIN_REGION}"
STEP_DELAY_MIN = float(os.getenv("STEP_DELAY_MIN", "0.5"))
STEP_DELAY_MAX = float(os.getenv("STEP_DELAY_MAX", "1.0"))

# ---------------------------------------------------------------------------
# Logging — structured JSON
# ---------------------------------------------------------------------------
class JSONFormatter(logging.Formatter):
    def format(self, record):
        log = {
            "timestamp": self.formatTime(record),
            "level": record.levelname,
            "message": record.getMessage(),
        }
        if hasattr(record, "scenario"):
            log["scenario"] = record.scenario
        if hasattr(record, "step"):
            log["step"] = record.step
        if hasattr(record, "status_code"):
            log["status_code"] = record.status_code
        if hasattr(record, "latency_ms"):
            log["latency_ms"] = record.latency_ms
        if hasattr(record, "trace_id"):
            log["trace_id"] = record.trace_id
        return json.dumps(log)

logger = logging.getLogger("synthetic-monitor")
logger.setLevel(logging.INFO)
handler = logging.StreamHandler()
handler.setFormatter(JSONFormatter())
logger.addHandler(handler)

# ---------------------------------------------------------------------------
# OpenTelemetry setup
# ---------------------------------------------------------------------------
resource = Resource.create({
    "service.name": os.getenv("OTEL_SERVICE_NAME", "synthetic-monitor"),
    "test.origin": ORIGIN_LABEL,
    "aws.region": ORIGIN_REGION,
})
provider = TracerProvider(resource=resource)
try:
    exporter = OTLPSpanExporter(endpoint=OTEL_ENDPOINT, insecure=True)
    provider.add_span_processor(BatchSpanProcessor(exporter))
except Exception as e:
    logger.warning(f"OTel exporter init failed (traces will be local only): {e}")
trace.set_tracer_provider(provider)
tracer = trace.get_tracer("synthetic-monitor")
propagator = TraceContextTextMapPropagator()


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
def api(session: requests.Session, method: str, path: str, scenario: str, step: str, body=None):
    """Execute one API call with trace propagation and structured logging."""
    url = f"{BASE_URL}{path}"
    headers = {"Content-Type": "application/json"}

    # Inject current trace context into headers
    ctx = trace.get_current_span().get_span_context()
    if ctx.is_valid:
        carrier = {}
        propagator.inject(carrier)
        headers.update(carrier)

    start = time.monotonic()
    try:
        resp = session.request(method, url, json=body, headers=headers, timeout=10)
        latency = round((time.monotonic() - start) * 1000, 1)
        extra = {"scenario": scenario, "step": step, "status_code": resp.status_code, "latency_ms": latency}
        if ctx.is_valid:
            extra["trace_id"] = format(ctx.trace_id, "032x")
        logger.info(f"{method} {path} -> {resp.status_code}", extra=extra)
        return resp
    except Exception as e:
        latency = round((time.monotonic() - start) * 1000, 1)
        extra = {"scenario": scenario, "step": step, "status_code": 0, "latency_ms": latency}
        logger.error(f"{method} {path} -> ERROR: {e}", extra=extra)
        return None


def delay():
    """Sleep between steps for realistic pacing."""
    import random
    time.sleep(random.uniform(STEP_DELAY_MIN, STEP_DELAY_MAX))


# ---------------------------------------------------------------------------
# Scenarios
# ---------------------------------------------------------------------------

def s1_browse_and_search(session: requests.Session):
    """S1: Browse & Search -> product-catalog, search, pricing, review, recommendation"""
    name = "s1_browse_and_search"
    with tracer.start_as_current_span(name):
        product_id = str(uuid.uuid4())

        api(session, "GET", "/api/v1/products", name, "list_products")
        delay()
        api(session, "GET", "/api/v1/products/categories", name, "list_categories")
        delay()
        api(session, "GET", "/api/v1/search?q=laptop", name, "search_laptop")
        delay()
        api(session, "GET", f"/api/v1/products/{product_id}", name, "get_product")
        delay()
        api(session, "GET", f"/api/v1/prices/{product_id}", name, "get_price")
        delay()
        api(session, "GET", f"/api/v1/reviews/product/{product_id}", name, "get_reviews")
        delay()
        api(session, "GET", f"/api/v1/recommendations/similar/{product_id}", name, "get_similar")


def s2_user_registration(session: requests.Session):
    """S2: User Registration & Profile -> user-account, user-profile, notification"""
    name = "s2_user_registration"
    with tracer.start_as_current_span(name):
        user_id = str(uuid.uuid4())
        email = f"synth-{user_id[:8]}@test.mall"

        api(session, "POST", "/api/v1/users/register", name, "register",
            {"email": email, "password": "SynthTest123!", "name": "Synthetic User"})
        delay()
        api(session, "POST", "/api/v1/users/login", name, "login",
            {"email": email, "password": "SynthTest123!"})
        delay()
        api(session, "GET", f"/api/v1/users/{user_id}", name, "get_user")
        delay()
        api(session, "GET", f"/api/v1/profiles/{user_id}", name, "get_profile")
        delay()
        api(session, "PUT", f"/api/v1/profiles/{user_id}", name, "update_profile",
            {"display_name": "Synthetic Shopper", "preferences": {"newsletter": False}})
        delay()
        api(session, "POST", f"/api/v1/profiles/{user_id}/addresses", name, "add_address",
            {"street": "123 Synthetic St", "city": "Testville", "state": "CA", "zip": "90210"})
        delay()
        api(session, "GET", f"/api/v1/notifications/{user_id}", name, "get_notifications")


def s3_shopping_cart(session: requests.Session):
    """S3: Shopping Cart -> product-catalog, inventory, cart, pricing, recommendation, wishlist"""
    name = "s3_shopping_cart"
    with tracer.start_as_current_span(name):
        user_id = str(uuid.uuid4())
        product_id1 = str(uuid.uuid4())
        product_id2 = str(uuid.uuid4())

        api(session, "GET", "/api/v1/products", name, "list_products")
        delay()
        api(session, "GET", f"/api/v1/inventory/{product_id1}", name, "check_inventory")
        delay()
        api(session, "POST", f"/api/v1/carts/{user_id}", name, "add_item_1",
            {"product_id": product_id1, "quantity": 1})
        delay()
        api(session, "POST", f"/api/v1/carts/{user_id}", name, "add_item_2",
            {"product_id": product_id2, "quantity": 2})
        delay()
        api(session, "GET", f"/api/v1/carts/{user_id}", name, "get_cart")
        delay()
        api(session, "POST", "/api/v1/prices/calculate", name, "calculate_price",
            {"items": [
                {"product_id": product_id1, "quantity": 1},
                {"product_id": product_id2, "quantity": 2},
            ]})
        delay()
        api(session, "GET", f"/api/v1/recommendations/{user_id}", name, "get_recommendations")
        delay()
        api(session, "POST", f"/api/v1/wishlists/{user_id}/items", name, "add_wishlist",
            {"product_id": product_id1})
        delay()
        api(session, "GET", f"/api/v1/wishlists/{user_id}", name, "get_wishlist")


def s4_purchase_flow(session: requests.Session):
    """S4: Purchase Flow -> order, payment, shipping"""
    name = "s4_purchase_flow"
    with tracer.start_as_current_span(name):
        user_id = str(uuid.uuid4())
        order_id = str(uuid.uuid4())
        payment_id = str(uuid.uuid4())
        shipment_id = str(uuid.uuid4())
        tracking = f"TRK-{uuid.uuid4().hex[:12].upper()}"

        api(session, "POST", "/api/v1/orders", name, "create_order",
            {"user_id": user_id, "items": [{"product_id": str(uuid.uuid4()), "quantity": 1}]})
        delay()
        api(session, "GET", f"/api/v1/orders/{order_id}", name, "get_order")
        delay()
        api(session, "POST", "/api/v1/payments", name, "create_payment",
            {"order_id": order_id, "amount": 99.99, "method": "credit_card"})
        delay()
        api(session, "GET", f"/api/v1/payments/{payment_id}", name, "get_payment")
        delay()
        api(session, "POST", "/api/v1/shipments", name, "create_shipment",
            {"order_id": order_id, "address": {"street": "456 Ship St", "city": "Malltown"}})
        delay()
        api(session, "GET", f"/api/v1/shipments/{shipment_id}", name, "get_shipment")
        delay()
        api(session, "GET", f"/api/v1/shipments/track/{tracking}", name, "track_shipment")


def s5_seller_and_warehouse(session: requests.Session):
    """S5: Seller & Warehouse -> seller, warehouse, inventory"""
    name = "s5_seller_and_warehouse"
    with tracer.start_as_current_span(name):
        seller_id = str(uuid.uuid4())
        warehouse_id = str(uuid.uuid4())

        api(session, "POST", "/api/v1/sellers/register", name, "register_seller",
            {"name": "Synthetic Seller", "email": f"seller-{seller_id[:8]}@test.mall"})
        delay()
        api(session, "GET", f"/api/v1/sellers/{seller_id}", name, "get_seller")
        delay()
        api(session, "GET", f"/api/v1/sellers/{seller_id}/products", name, "get_seller_products")
        delay()
        api(session, "GET", "/api/v1/warehouses", name, "list_warehouses")
        delay()
        api(session, "GET", f"/api/v1/warehouses/{warehouse_id}/stock", name, "get_warehouse_stock")
        delay()
        api(session, "GET", "/api/v1/inventory/low-stock", name, "check_low_stock")


def s6_post_purchase(session: requests.Session):
    """S6: Post-Purchase -> review, returns, notification"""
    name = "s6_post_purchase"
    with tracer.start_as_current_span(name):
        user_id = str(uuid.uuid4())
        product_id = str(uuid.uuid4())
        review_id = str(uuid.uuid4())
        return_id = str(uuid.uuid4())

        api(session, "POST", "/api/v1/reviews", name, "create_review",
            {"user_id": user_id, "product_id": product_id, "rating": 4, "text": "Synthetic review"})
        delay()
        api(session, "GET", f"/api/v1/reviews/{review_id}", name, "get_review")
        delay()
        api(session, "POST", "/api/v1/returns", name, "create_return",
            {"order_id": str(uuid.uuid4()), "reason": "synthetic_test", "items": [product_id]})
        delay()
        api(session, "GET", f"/api/v1/returns/{return_id}", name, "get_return")
        delay()
        api(session, "POST", "/api/v1/notifications/send", name, "send_notification",
            {"user_id": user_id, "type": "order_update", "message": "Synthetic test notification"})
        delay()
        api(session, "GET", f"/api/v1/notifications/{user_id}", name, "get_notifications")


def s7_platform_and_analytics(session: requests.Session):
    """S7: Platform & Analytics -> event-bus, analytics, recommendation"""
    name = "s7_platform_and_analytics"
    with tracer.start_as_current_span(name):
        api(session, "POST", "/api/v1/events", name, "publish_event",
            {"topic": "synthetic.test", "payload": {"run_id": str(uuid.uuid4())}})
        delay()
        api(session, "GET", "/api/v1/events/topics", name, "list_topics")
        delay()
        api(session, "GET", "/api/v1/analytics/dashboard", name, "get_dashboard")
        delay()
        api(session, "POST", "/api/v1/analytics/events", name, "track_analytics",
            {"event": "page_view", "page": "/synthetic", "timestamp": int(time.time())})
        delay()
        api(session, "GET", "/api/v1/recommendations/trending", name, "get_trending")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
SCENARIOS = [
    s1_browse_and_search,
    s2_user_registration,
    s3_shopping_cart,
    s4_purchase_flow,
    s5_seller_and_warehouse,
    s6_post_purchase,
    s7_platform_and_analytics,
]


def main():
    run_id = uuid.uuid4().hex[:8]
    logger.info(f"Starting synthetic monitor run={run_id} origin={ORIGIN_LABEL} base_url={BASE_URL}")

    session = requests.Session()
    session.headers.update({"User-Agent": f"SyntheticMonitor/{ORIGIN_LABEL}/{run_id}"})

    passed, failed = 0, 0
    for scenario_fn in SCENARIOS:
        try:
            scenario_fn(session)
            passed += 1
        except Exception as e:
            failed += 1
            logger.error(f"Scenario {scenario_fn.__name__} failed: {e}",
                         extra={"scenario": scenario_fn.__name__})

    logger.info(f"Completed run={run_id} passed={passed} failed={failed}")

    # Flush OTel spans
    provider.force_flush(timeout_millis=5000)


if __name__ == "__main__":
    main()
