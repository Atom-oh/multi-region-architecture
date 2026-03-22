package com.mall.order;

import jakarta.servlet.http.HttpServletRequest;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.*;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.client.RestTemplate;

import java.math.BigDecimal;
import java.sql.Timestamp;
import java.util.*;

@RestController
@CrossOrigin(origins = "*", allowedHeaders = "*", methods = {RequestMethod.GET, RequestMethod.POST, RequestMethod.PUT, RequestMethod.DELETE, RequestMethod.OPTIONS})
public class Controller {

    private final RestTemplate restTemplate = new RestTemplate();

    @Autowired(required = false)
    private JdbcTemplate jdbcTemplate;

    @GetMapping("/")
    public Map<String, Object> root() {
        return Map.of(
            "service", "order-service",
            "version", "1.0.0",
            "status", "running"
        );
    }

    @GetMapping("/health/ready")
    public Map<String, String> ready() {
        return Map.of("status", "ready");
    }

    @GetMapping("/health/live")
    public Map<String, String> live() {
        return Map.of("status", "alive");
    }

    @GetMapping("/health/startup")
    public Map<String, String> startup() {
        return Map.of("status", "started");
    }

    @PostMapping("/api/v1/orders")
    public ResponseEntity<Map<String, Object>> createOrder(@RequestBody Map<String, Object> order, HttpServletRequest request) {
        String userId = (String) order.getOrDefault("user_id", "USR-001");
        List<?> items = (List<?>) order.getOrDefault("items", List.of());

        // Extract product ID from first item for inventory check
        String productId = "PRD-001";
        if (!items.isEmpty() && items.get(0) instanceof Map) {
            Object pid = ((Map<?, ?>) items.get(0)).get("product_id");
            if (pid != null) productId = pid.toString();
        }

        // Step 1: Check inventory (distributed trace: order -> inventory)
        Map<String, Object> inventoryCheck = callService(
            "http://inventory.core-services.svc.cluster.local:80/api/v1/inventory/" + productId,
            HttpMethod.GET, null, request);

        // Step 2: Create payment (distributed trace: order -> payment)
        Map<String, Object> paymentBody = new LinkedHashMap<>();
        paymentBody.put("order_id", "ORD-NEW-001");
        paymentBody.put("amount", order.getOrDefault("total_amount", 99000));
        paymentBody.put("method", "credit_card");
        Map<String, Object> paymentResult = callService(
            "http://payment.core-services.svc.cluster.local:80/api/v1/payments",
            HttpMethod.POST, paymentBody, request);

        // Step 3: Create shipment (distributed trace: order -> shipping)
        Map<String, Object> shippingBody = new LinkedHashMap<>();
        shippingBody.put("order_id", "ORD-NEW-001");
        shippingBody.put("address", Map.of("street", "서울시 강남구 테헤란로 123", "city", "Seoul"));
        Map<String, Object> shippingResult = callService(
            "http://shipping.fulfillment.svc.cluster.local:80/api/v1/shipments",
            HttpMethod.POST, shippingBody, request);

        String orderId = "ORD-NEW-001";
        BigDecimal totalAmount = new BigDecimal(order.getOrDefault("total_amount", 0).toString());

        // Try to insert into DB if available
        if (jdbcTemplate != null) {
            try {
                UUID newOrderId = UUID.randomUUID();
                jdbcTemplate.update(
                    "INSERT INTO orders (id, user_id, status, total_amount, currency, created_at, updated_at) VALUES (?::uuid, ?::uuid, ?, ?, ?, NOW(), NOW())",
                    newOrderId.toString(), userId.startsWith("USR-") ? UUID.randomUUID().toString() : userId,
                    "pending", totalAmount, "KRW"
                );
                orderId = newOrderId.toString();
            } catch (Exception e) {
                // Fall back to mock ID
            }
        }

        Map<String, Object> response = new LinkedHashMap<>();
        response.put("id", orderId);
        response.put("user_id", userId);
        response.put("items", items);
        response.put("total_amount", order.getOrDefault("total_amount", 0));
        response.put("currency", "KRW");
        response.put("status", "pending");
        response.put("status_display", "주문접수");
        response.put("inventory_check", inventoryCheck);
        response.put("payment", paymentResult);
        response.put("shipping", shippingResult);
        response.put("created_at", "2026-03-20T10:00:00Z");
        response.put("message", "주문이 접수되었습니다");

        return ResponseEntity.ok()
            .header(HttpHeaders.ACCESS_CONTROL_ALLOW_ORIGIN, "*")
            .body(response);
    }

    @GetMapping("/api/v1/orders")
    public ResponseEntity<List<Map<String, Object>>> getOrders() {
        if (jdbcTemplate != null) {
            try {
                List<Map<String, Object>> orders = jdbcTemplate.queryForList(
                    "SELECT id, user_id, status, total_amount, currency, created_at FROM orders ORDER BY created_at DESC LIMIT 20"
                );
                List<Map<String, Object>> result = new ArrayList<>();
                for (Map<String, Object> row : orders) {
                    Map<String, Object> order = new LinkedHashMap<>();
                    order.put("id", row.get("id").toString());
                    order.put("user_id", row.get("user_id") != null ? row.get("user_id").toString() : "USR-001");
                    order.put("total_amount", row.get("total_amount"));
                    order.put("currency", row.get("currency"));
                    order.put("status", row.get("status"));
                    order.put("status_display", getStatusDisplay((String) row.get("status")));
                    order.put("created_at", row.get("created_at").toString());
                    result.add(order);
                }
                if (!result.isEmpty()) {
                    return ResponseEntity.ok()
                        .header(HttpHeaders.ACCESS_CONTROL_ALLOW_ORIGIN, "*")
                        .body(result);
                }
            } catch (Exception e) {
                // Fall back to mock data
            }
        }

        // Mock data fallback
        List<Map<String, Object>> orders = List.of(
            Map.ofEntries(
                Map.entry("id", "ORD-001"),
                Map.entry("user_id", "USR-001"),
                Map.entry("user_name", "김민수"),
                Map.entry("items", List.of(
                    Map.of("product_id", "PRD-001", "name", "삼성 갤럭시 S25 울트라", "quantity", 1, "price", 1890000),
                    Map.of("product_id", "PRD-010", "name", "소니 WH-1000XM5", "quantity", 1, "price", 429000)
                )),
                Map.entry("total_amount", 2319000),
                Map.entry("currency", "KRW"),
                Map.entry("status", "delivered"),
                Map.entry("status_display", "배송완료"),
                Map.entry("created_at", "2026-03-15T14:30:00Z")
            ),
            Map.ofEntries(
                Map.entry("id", "ORD-002"),
                Map.entry("user_id", "USR-002"),
                Map.entry("user_name", "이서연"),
                Map.entry("items", List.of(
                    Map.of("product_id", "PRD-003", "name", "다이슨 에어랩", "quantity", 1, "price", 699000)
                )),
                Map.entry("total_amount", 699000),
                Map.entry("currency", "KRW"),
                Map.entry("status", "shipping"),
                Map.entry("status_display", "배송중"),
                Map.entry("created_at", "2026-03-18T11:20:00Z")
            ),
            Map.ofEntries(
                Map.entry("id", "ORD-003"),
                Map.entry("user_id", "USR-003"),
                Map.entry("user_name", "박지훈"),
                Map.entry("items", List.of(
                    Map.of("product_id", "PRD-002", "name", "나이키 에어맥스 97", "quantity", 1, "price", 189000),
                    Map.of("product_id", "PRD-008", "name", "무지 캔버스 토트백", "quantity", 1, "price", 29000)
                )),
                Map.entry("total_amount", 218000),
                Map.entry("currency", "KRW"),
                Map.entry("status", "processing"),
                Map.entry("status_display", "상품준비중"),
                Map.entry("created_at", "2026-03-20T09:45:00Z")
            )
        );
        return ResponseEntity.ok()
            .header(HttpHeaders.ACCESS_CONTROL_ALLOW_ORIGIN, "*")
            .body(orders);
    }

    @GetMapping("/api/v1/orders/{id}")
    public ResponseEntity<Map<String, Object>> getOrder(@PathVariable String id) {
        if (jdbcTemplate != null) {
            try {
                // Try to fetch from DB (handle both UUID and mock IDs)
                List<Map<String, Object>> orders = jdbcTemplate.queryForList(
                    "SELECT * FROM orders WHERE id::text = ?", id
                );
                if (!orders.isEmpty()) {
                    Map<String, Object> row = orders.get(0);
                    List<Map<String, Object>> items = jdbcTemplate.queryForList(
                        "SELECT * FROM order_items WHERE order_id::text = ?", id
                    );

                    Map<String, Object> order = new LinkedHashMap<>();
                    order.put("id", row.get("id").toString());
                    order.put("user_id", row.get("user_id") != null ? row.get("user_id").toString() : "USR-001");
                    order.put("items", items.isEmpty() ? List.of() : items);
                    order.put("total_amount", row.get("total_amount"));
                    order.put("currency", row.get("currency"));
                    order.put("status", row.get("status"));
                    order.put("status_display", getStatusDisplay((String) row.get("status")));
                    order.put("created_at", row.get("created_at").toString());

                    return ResponseEntity.ok()
                        .header(HttpHeaders.ACCESS_CONTROL_ALLOW_ORIGIN, "*")
                        .body(order);
                }
            } catch (Exception e) {
                // Fall back to mock data
            }
        }

        // Mock data fallback
        Map<String, Object> order;
        switch (id) {
            case "ORD-001":
                order = Map.ofEntries(
                    Map.entry("id", "ORD-001"),
                    Map.entry("user_id", "USR-001"),
                    Map.entry("user_name", "김민수"),
                    Map.entry("items", List.of(
                        Map.of("product_id", "PRD-001", "name", "삼성 갤럭시 S25 울트라", "quantity", 1, "price", 1890000, "image_url", "https://placehold.co/100x100/EEE/333?text=Galaxy"),
                        Map.of("product_id", "PRD-010", "name", "소니 WH-1000XM5", "quantity", 1, "price", 429000, "image_url", "https://placehold.co/100x100/EEE/333?text=Sony")
                    )),
                    Map.entry("subtotal", 2319000),
                    Map.entry("shipping_fee", 0),
                    Map.entry("discount", 0),
                    Map.entry("total_amount", 2319000),
                    Map.entry("currency", "KRW"),
                    Map.entry("status", "delivered"),
                    Map.entry("status_display", "배송완료"),
                    Map.entry("shipping_address", Map.of(
                        "name", "김민수",
                        "phone", "010-1234-5678",
                        "address", "서울특별시 강남구 테헤란로 123 멀티리전타워 15층",
                        "zip", "06234"
                    )),
                    Map.entry("payment_method", "신용카드"),
                    Map.entry("created_at", "2026-03-15T14:30:00Z"),
                    Map.entry("delivered_at", "2026-03-18T14:32:00Z")
                );
                break;
            case "ORD-002":
                order = Map.ofEntries(
                    Map.entry("id", "ORD-002"),
                    Map.entry("user_id", "USR-002"),
                    Map.entry("user_name", "이서연"),
                    Map.entry("items", List.of(
                        Map.of("product_id", "PRD-003", "name", "다이슨 에어랩", "quantity", 1, "price", 699000, "image_url", "https://placehold.co/100x100/EEE/333?text=Dyson")
                    )),
                    Map.entry("subtotal", 699000),
                    Map.entry("shipping_fee", 0),
                    Map.entry("discount", 0),
                    Map.entry("total_amount", 699000),
                    Map.entry("currency", "KRW"),
                    Map.entry("status", "shipping"),
                    Map.entry("status_display", "배송중"),
                    Map.entry("tracking_number", "HANJIN9876543210"),
                    Map.entry("shipping_address", Map.of(
                        "name", "이서연",
                        "phone", "010-9876-5432",
                        "address", "서울특별시 서초구 강남대로 456 힐스테이트 1203호",
                        "zip", "06612"
                    )),
                    Map.entry("payment_method", "카카오페이"),
                    Map.entry("created_at", "2026-03-18T11:20:00Z")
                );
                break;
            case "ORD-003":
                order = Map.ofEntries(
                    Map.entry("id", "ORD-003"),
                    Map.entry("user_id", "USR-003"),
                    Map.entry("user_name", "박지훈"),
                    Map.entry("items", List.of(
                        Map.of("product_id", "PRD-002", "name", "나이키 에어맥스 97", "quantity", 1, "price", 189000, "image_url", "https://placehold.co/100x100/EEE/333?text=Nike"),
                        Map.of("product_id", "PRD-008", "name", "무지 캔버스 토트백", "quantity", 1, "price", 29000, "image_url", "https://placehold.co/100x100/EEE/333?text=MUJI")
                    )),
                    Map.entry("subtotal", 218000),
                    Map.entry("shipping_fee", 0),
                    Map.entry("discount", 0),
                    Map.entry("total_amount", 218000),
                    Map.entry("currency", "KRW"),
                    Map.entry("status", "processing"),
                    Map.entry("status_display", "상품준비중"),
                    Map.entry("shipping_address", Map.of(
                        "name", "박지훈",
                        "phone", "010-5555-7777",
                        "address", "부산광역시 해운대구 해운대로 789 마린시티 2501호",
                        "zip", "48099"
                    )),
                    Map.entry("payment_method", "네이버페이"),
                    Map.entry("created_at", "2026-03-20T09:45:00Z")
                );
                break;
            default:
                order = Map.of(
                    "id", id,
                    "error", "주문을 찾을 수 없습니다",
                    "status", "not_found"
                );
        }
        return ResponseEntity.ok()
            .header(HttpHeaders.ACCESS_CONTROL_ALLOW_ORIGIN, "*")
            .body(order);
    }

    @GetMapping("/api/v1/orders/user/{userId}")
    public ResponseEntity<Map<String, Object>> getOrdersByUser(@PathVariable String userId) {
        if (jdbcTemplate != null) {
            try {
                List<Map<String, Object>> orders = jdbcTemplate.queryForList(
                    "SELECT id, total_amount, status, created_at FROM orders WHERE user_id::text = ?", userId
                );
                if (!orders.isEmpty()) {
                    List<Map<String, Object>> result = new ArrayList<>();
                    for (Map<String, Object> row : orders) {
                        Map<String, Object> order = new LinkedHashMap<>();
                        order.put("id", row.get("id").toString());
                        order.put("total_amount", row.get("total_amount"));
                        order.put("status", row.get("status"));
                        order.put("status_display", getStatusDisplay((String) row.get("status")));
                        order.put("created_at", row.get("created_at").toString());
                        result.add(order);
                    }
                    Map<String, Object> response = Map.of(
                        "user_id", userId,
                        "orders", result,
                        "total", result.size()
                    );
                    return ResponseEntity.ok()
                        .header(HttpHeaders.ACCESS_CONTROL_ALLOW_ORIGIN, "*")
                        .body(response);
                }
            } catch (Exception e) {
                // Fall back to mock data
            }
        }

        // Mock data fallback
        List<Map<String, Object>> orders;
        switch (userId) {
            case "USR-001":
                orders = List.of(
                    Map.of("id", "ORD-001", "total_amount", 2319000, "item_count", 2, "status", "delivered", "status_display", "배송완료", "created_at", "2026-03-15T14:30:00Z")
                );
                break;
            case "USR-002":
                orders = List.of(
                    Map.of("id", "ORD-002", "total_amount", 699000, "item_count", 1, "status", "shipping", "status_display", "배송중", "created_at", "2026-03-18T11:20:00Z")
                );
                break;
            case "USR-003":
                orders = List.of(
                    Map.of("id", "ORD-003", "total_amount", 218000, "item_count", 2, "status", "processing", "status_display", "상품준비중", "created_at", "2026-03-20T09:45:00Z")
                );
                break;
            default:
                orders = List.of();
        }
        Map<String, Object> response = Map.of(
            "user_id", userId,
            "orders", orders,
            "total", orders.size()
        );
        return ResponseEntity.ok()
            .header(HttpHeaders.ACCESS_CONTROL_ALLOW_ORIGIN, "*")
            .body(response);
    }

    private String getStatusDisplay(String status) {
        if (status == null) return "알 수 없음";
        switch (status) {
            case "pending": return "주문접수";
            case "processing": return "상품준비중";
            case "shipping": return "배송중";
            case "delivered": return "배송완료";
            case "cancelled": return "주문취소";
            case "returned": return "반품완료";
            default: return status;
        }
    }

    @SuppressWarnings("unchecked")
    private Map<String, Object> callService(String url, HttpMethod method, Map<String, Object> body, HttpServletRequest request) {
        try {
            HttpHeaders headers = new HttpHeaders();
            headers.setContentType(MediaType.APPLICATION_JSON);
            // Forward W3C trace context for distributed tracing
            String traceparent = request.getHeader("traceparent");
            if (traceparent != null) headers.set("traceparent", traceparent);
            String tracestate = request.getHeader("tracestate");
            if (tracestate != null) headers.set("tracestate", tracestate);

            HttpEntity<?> entity = body != null
                ? new HttpEntity<>(body, headers)
                : new HttpEntity<>(headers);

            ResponseEntity<Map> resp = restTemplate.exchange(url, method, entity, Map.class);
            return resp.getBody() != null ? resp.getBody() : Map.of("status", "ok");
        } catch (Exception e) {
            return Map.of("status", "fallback", "message", "서비스 호출 실패 - mock 데이터 사용");
        }
    }
}
