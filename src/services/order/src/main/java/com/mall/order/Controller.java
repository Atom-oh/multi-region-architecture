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

        // Empty fallback - no mock data
        return ResponseEntity.ok()
            .header(HttpHeaders.ACCESS_CONTROL_ALLOW_ORIGIN, "*")
            .body(List.of());
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

        // Empty fallback - no mock data
        Map<String, Object> order = Map.of(
            "id", id,
            "error", "주문을 찾을 수 없습니다",
            "status", "not_found"
        );
        return ResponseEntity.ok()
            .header(HttpHeaders.ACCESS_CONTROL_ALLOW_ORIGIN, "*")
            .body(order);
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

        // Empty fallback - no mock data
        List<Map<String, Object>> orders = List.of();
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
