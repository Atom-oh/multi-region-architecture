package com.mall.order;

import jakarta.servlet.http.HttpServletRequest;
import org.springframework.beans.factory.annotation.Autowired;
import org.apache.hc.client5.http.impl.classic.CloseableHttpClient;
import org.apache.hc.client5.http.impl.classic.HttpClients;
import org.apache.hc.client5.http.impl.io.PoolingHttpClientConnectionManager;
import org.springframework.http.*;
import org.springframework.http.client.HttpComponentsClientHttpRequestFactory;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.client.RestTemplate;

import java.math.BigDecimal;
import java.sql.Timestamp;
import java.util.*;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.TimeoutException;

@RestController
@CrossOrigin(origins = "*", allowedHeaders = "*", methods = {RequestMethod.GET, RequestMethod.POST, RequestMethod.PUT, RequestMethod.DELETE, RequestMethod.OPTIONS})
public class Controller {

    private final RestTemplate restTemplate;
    {
        PoolingHttpClientConnectionManager cm = new PoolingHttpClientConnectionManager();
        cm.setMaxTotal(100);
        cm.setDefaultMaxPerRoute(20);
        CloseableHttpClient httpClient = HttpClients.custom()
            .setConnectionManager(cm)
            .build();
        HttpComponentsClientHttpRequestFactory factory = new HttpComponentsClientHttpRequestFactory(httpClient);
        factory.setConnectTimeout(3000);
        factory.setConnectionRequestTimeout(3000);
        factory.setReadTimeout(5000);
        restTemplate = new RestTemplate(factory);
    }

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
        String userId = (String) order.getOrDefault("user_id", "unknown");
        List<?> items = (List<?>) order.getOrDefault("items", List.of());

        // Extract product ID from first item for inventory check
        String productId = null;
        if (!items.isEmpty() && items.get(0) instanceof Map) {
            Object pid = ((Map<?, ?>) items.get(0)).get("product_id");
            if (pid != null) productId = pid.toString();
        }

        // Generate order ID up front so all service calls reference the same ID
        String orderId = UUID.randomUUID().toString();

        // Parallel service calls: inventory, payment, shipping (distributed traces)
        Map<String, Object> paymentBody = new LinkedHashMap<>();
        paymentBody.put("order_id", orderId);
        paymentBody.put("amount", order.getOrDefault("total_amount", 99000));
        paymentBody.put("method", "credit_card");

        Map<String, Object> shippingBody = new LinkedHashMap<>();
        shippingBody.put("order_id", orderId);
        shippingBody.put("address", order.getOrDefault("shipping_address", Map.of("street", "서울시 강남구 테헤란로 123", "city", "Seoul")));

        String inventoryUrl = productId != null
            ? "http://inventory.core-services.svc.cluster.local:80/api/v1/inventory/" + productId
            : null;
        String paymentUrl = "http://payment.core-services.svc.cluster.local:80/api/v1/payments";
        String shippingUrl = "http://shipping.fulfillment.svc.cluster.local:80/api/v1/shipments";

        CompletableFuture<Map<String, Object>> inventoryFuture = inventoryUrl != null
            ? CompletableFuture.supplyAsync(() -> callService(inventoryUrl, HttpMethod.GET, null, request))
            : CompletableFuture.completedFuture(Map.of("status", "skipped", "message", "상품 ID 없음"));
        CompletableFuture<Map<String, Object>> paymentFuture = CompletableFuture.supplyAsync(
            () -> callService(paymentUrl, HttpMethod.POST, paymentBody, request));
        CompletableFuture<Map<String, Object>> shippingFuture = CompletableFuture.supplyAsync(
            () -> callService(shippingUrl, HttpMethod.POST, shippingBody, request));

        try {
            CompletableFuture.allOf(inventoryFuture, paymentFuture, shippingFuture)
                .get(8, TimeUnit.SECONDS);
        } catch (TimeoutException e) {
            // Cancel remaining futures on timeout
            inventoryFuture.cancel(true);
            paymentFuture.cancel(true);
            shippingFuture.cancel(true);
        } catch (Exception e) {
            // InterruptedException or ExecutionException — proceed with available results
        }

        Map<String, Object> inventoryCheck = inventoryFuture.isDone() && !inventoryFuture.isCompletedExceptionally()
            ? inventoryFuture.join() : Map.of("status", "timeout", "message", "재고 확인 타임아웃");
        Map<String, Object> paymentResult = paymentFuture.isDone() && !paymentFuture.isCompletedExceptionally()
            ? paymentFuture.join() : Map.of("status", "timeout", "message", "결제 처리 타임아웃");
        Map<String, Object> shippingResult = shippingFuture.isDone() && !shippingFuture.isCompletedExceptionally()
            ? shippingFuture.join() : Map.of("status", "timeout", "message", "배송 요청 타임아웃");

        BigDecimal totalAmount = new BigDecimal(order.getOrDefault("total_amount", 0).toString());

        // Try to insert into DB if available
        if (jdbcTemplate != null) {
            try {
                jdbcTemplate.update(
                    "INSERT INTO orders (id, user_id, status, total_amount, currency, created_at, updated_at) VALUES (?::uuid, ?::uuid, ?, ?, ?, NOW(), NOW())",
                    orderId, userId,
                    "pending", totalAmount, "KRW"
                );
            } catch (Exception e) {
                System.err.println("주문 DB 저장 실패 (orderId=" + orderId + "): " + e.getMessage());
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

        // TODO: Publish to Kafka topic "orders.created"
        // Requires spring-kafka dependency to be added to pom.xml
        // Map<String, Object> orderEvent = new LinkedHashMap<>();
        // orderEvent.put("event_type", "order.created");
        // orderEvent.put("order_id", orderId);
        // orderEvent.put("user_id", userId);
        // orderEvent.put("items", items);
        // orderEvent.put("total_amount", order.getOrDefault("total_amount", 0));
        // orderEvent.put("timestamp", Instant.now().toString());
        // kafkaTemplate.send("orders.created", orderId, orderEvent);

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
                    order.put("user_id", row.get("user_id") != null ? row.get("user_id").toString() : null);
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
                // Fall back to empty result
            }
        }

        // Demo fallback with real catalog products
        return ResponseEntity.ok()
            .header(HttpHeaders.ACCESS_CONTROL_ALLOW_ORIGIN, "*")
            .body(getDemoOrders());
    }

    @GetMapping("/api/v1/orders/{id}")
    public ResponseEntity<Map<String, Object>> getOrder(@PathVariable String id) {
        if (jdbcTemplate != null) {
            try {
                // Try to fetch from DB (handle both UUID and mock IDs)
                List<Map<String, Object>> orders = jdbcTemplate.queryForList(
                    "SELECT * FROM orders WHERE id = ?::uuid", id
                );
                if (!orders.isEmpty()) {
                    Map<String, Object> row = orders.get(0);
                    List<Map<String, Object>> items = jdbcTemplate.queryForList(
                        "SELECT * FROM order_items WHERE order_id = ?::uuid", id
                    );

                    Map<String, Object> order = new LinkedHashMap<>();
                    order.put("id", row.get("id").toString());
                    order.put("user_id", row.get("user_id") != null ? row.get("user_id").toString() : null);
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
                // Fall back to empty result
            }
        }

        // Check demo orders fallback
        for (Map<String, Object> demo : getDemoOrders()) {
            if (id.equals(demo.get("id"))) {
                return ResponseEntity.ok()
                    .header(HttpHeaders.ACCESS_CONTROL_ALLOW_ORIGIN, "*")
                    .body(demo);
            }
        }
        return ResponseEntity.ok()
            .header(HttpHeaders.ACCESS_CONTROL_ALLOW_ORIGIN, "*")
            .body(Map.of("id", id, "error", "주문을 찾을 수 없습니다", "status", "not_found"));
    }

    @GetMapping("/api/v1/orders/user/{userId}")
    public ResponseEntity<Map<String, Object>> getOrdersByUser(@PathVariable String userId) {
        if (jdbcTemplate != null) {
            try {
                List<Map<String, Object>> orders = jdbcTemplate.queryForList(
                    "SELECT id, total_amount, status, created_at FROM orders WHERE user_id = ?::uuid", userId
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
                // Fall back to empty result
            }
        }

        // Filter demo orders by user
        List<Map<String, Object>> userOrders = new ArrayList<>();
        for (Map<String, Object> demo : getDemoOrders()) {
            if (userId.equals(demo.get("user_id"))) userOrders.add(demo);
        }
        return ResponseEntity.ok()
            .header(HttpHeaders.ACCESS_CONTROL_ALLOW_ORIGIN, "*")
            .body(Map.of("user_id", userId, "orders", userOrders, "total", userOrders.size()));
    }

    private List<Map<String, Object>> getDemoOrders() {
        List<Map<String, Object>> orders = new ArrayList<>();

        Map<String, Object> o1 = new LinkedHashMap<>();
        o1.put("id", "demo-ord-001");
        o1.put("user_id", "a0000001-0000-0000-0000-000000000001");
        o1.put("user_name", "김민지");
        o1.put("status", "delivered");
        o1.put("status_display", "배송완료");
        o1.put("total_amount", 1969851);
        o1.put("currency", "KRW");
        o1.put("items", List.of(
            Map.of("product_id", "PROD-0001", "name", "갤럭시S26 울트라 512GB, 자급제", "quantity", 1, "price", 1683571),
            Map.of("product_id", "PROD-0102", "name", "레볼루션 8 HJ9198-003", "quantity", 1, "price", 38256),
            Map.of("product_id", "PROD-0202", "name", "신라면 120g", "quantity", 10, "price", 2359)
        ));
        o1.put("created_at", "2026-04-10T14:30:00Z");
        orders.add(o1);

        Map<String, Object> o2 = new LinkedHashMap<>();
        o2.put("id", "demo-ord-002");
        o2.put("user_id", "a0000001-0000-0000-0000-000000000002");
        o2.put("user_name", "이서연");
        o2.put("status", "shipping");
        o2.put("status_display", "배송중");
        o2.put("total_amount", 1327168);
        o2.put("currency", "KRW");
        o2.put("items", List.of(
            Map.of("product_id", "PROD-0012", "name", "아이폰17 256GB, 자급제", "quantity", 1, "price", 1092384),
            Map.of("product_id", "PROD-0301", "name", "마다가스카르 센텔라 히알루-시카 워터핏 선세럼50ml", "quantity", 2, "price", 16418),
            Map.of("product_id", "PROD-0801", "name", "아레나 멀티 게이밍 책상 (1600x800)", "quantity", 1, "price", 122168)
        ));
        o2.put("created_at", "2026-04-14T11:20:00Z");
        orders.add(o2);

        Map<String, Object> o3 = new LinkedHashMap<>();
        o3.put("id", "demo-ord-003");
        o3.put("user_id", "a0000001-0000-0000-0000-000000000003");
        o3.put("user_name", "박지훈");
        o3.put("status", "processing");
        o3.put("status_display", "상품준비중");
        o3.put("total_amount", 758511);
        o3.put("currency", "KRW");
        o3.put("items", List.of(
            Map.of("product_id", "PROD-0503", "name", "아디제로 SL2 M JQ0351", "quantity", 1, "price", 86361),
            Map.of("product_id", "PROD-0401", "name", "블루스카이 5500 AP70F06103RTD", "quantity", 1, "price", 237560),
            Map.of("product_id", "PROD-0601", "name", "The Frozen River: A GMA Book Club Pick", "quantity", 2, "price", 13276),
            Map.of("product_id", "PROD-0901", "name", "요요3 프리미엄 휴대용유모차", "quantity", 1, "price", 615600)
        ));
        o3.put("created_at", "2026-04-16T09:45:00Z");
        orders.add(o3);

        Map<String, Object> o4 = new LinkedHashMap<>();
        o4.put("id", "demo-ord-004");
        o4.put("user_id", "a0000001-0000-0000-0000-000000000001");
        o4.put("user_name", "김민지");
        o4.put("status", "pending");
        o4.put("status_display", "주문접수");
        o4.put("total_amount", 2261170);
        o4.put("currency", "KRW");
        o4.put("items", List.of(
            Map.of("product_id", "PROD-0007", "name", "갤럭시Z 폴드7 512GB, 자급제", "quantity", 1, "price", 2261170)
        ));
        o4.put("created_at", "2026-04-17T16:00:00Z");
        orders.add(o4);

        Map<String, Object> o5 = new LinkedHashMap<>();
        o5.put("id", "demo-ord-005");
        o5.put("user_id", "a0000001-0000-0000-0000-000000000004");
        o5.put("user_name", "최수현");
        o5.put("status", "cancelled");
        o5.put("status_display", "주문취소");
        o5.put("total_amount", 507398);
        o5.put("currency", "KRW");
        o5.put("items", List.of(
            Map.of("product_id", "PROD-0402", "name", "퓨리케어 360˚ 플러스 AS305DWWA", "quantity", 1, "price", 507398)
        ));
        o5.put("created_at", "2026-04-12T08:15:00Z");
        orders.add(o5);

        return orders;
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
            // OTel Java Agent auto-instruments RestTemplate to inject correct child span traceparent

            HttpEntity<?> entity = body != null
                ? new HttpEntity<>(body, headers)
                : new HttpEntity<>(headers);

            ResponseEntity<Map> resp = restTemplate.exchange(url, method, entity, Map.class);
            return resp.getBody() != null ? resp.getBody() : Map.of("status", "ok");
        } catch (Exception e) {
            return Map.of("status", "fallback", "message", "서비스 호출 실패");
        }
    }
}
