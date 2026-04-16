package com.mall.returns;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.apache.hc.client5.http.impl.classic.CloseableHttpClient;
import org.apache.hc.client5.http.impl.classic.HttpClients;
import org.apache.hc.client5.http.impl.io.PoolingHttpClientConnectionManager;
import org.springframework.http.HttpHeaders;
import org.springframework.http.ResponseEntity;
import org.springframework.http.client.HttpComponentsClientHttpRequestFactory;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.client.RestTemplate;

import java.util.*;

@RestController
@CrossOrigin(origins = "*", allowedHeaders = "*", methods = {RequestMethod.GET, RequestMethod.POST, RequestMethod.PUT, RequestMethod.DELETE, RequestMethod.OPTIONS})
public class Controller {

    private static final Logger logger = LoggerFactory.getLogger(Controller.class);

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
        factory.setConnectionRequestTimeout(5000);
        restTemplate = new RestTemplate(factory);
    }

    @Autowired(required = false)
    private JdbcTemplate jdbcTemplate;

    @GetMapping("/")
    public Map<String, Object> root() {
        return Map.of(
            "service", "returns-service",
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

    @PostMapping("/api/v1/returns")
    public ResponseEntity<Map<String, Object>> createReturn(@RequestBody Map<String, Object> returnRequest) {
        Map<String, Object> response = Map.ofEntries(
            Map.entry("id", "RET-NEW-001"),
            Map.entry("order_id", returnRequest.getOrDefault("order_id", "ORD-001")),
            Map.entry("user_id", returnRequest.getOrDefault("user_id", "unknown")),
            Map.entry("reason", returnRequest.getOrDefault("reason", "단순변심")),
            Map.entry("reason_detail", returnRequest.getOrDefault("reason_detail", "")),
            Map.entry("status", "pending"),
            Map.entry("status_display", "반품접수"),
            Map.entry("pickup_scheduled", "2026-03-22T10:00:00Z"),
            Map.entry("created_at", "2026-03-20T10:00:00Z"),
            Map.entry("message", "반품 신청이 접수되었습니다. 택배 기사가 방문 예정입니다.")
        );
        return ResponseEntity.ok()
            .header(HttpHeaders.ACCESS_CONTROL_ALLOW_ORIGIN, "*")
            .body(response);
    }

    @GetMapping("/api/v1/returns")
    public ResponseEntity<Map<String, Object>> getReturns(
        @RequestParam(required = false) String user_id
    ) {
        // Inter-service call to order service instead of direct DB query
        String orderServiceUrl = System.getenv("ORDER_SERVICE_URL") != null
            ? System.getenv("ORDER_SERVICE_URL")
            : "http://order.core-services.svc.cluster.local:80";
        try {
            String url = orderServiceUrl + "/api/v1/orders?status=returned"
                + (user_id != null ? "&user_id=" + user_id : "")
                + "&limit=20";
            @SuppressWarnings("unchecked")
            Map<String, Object> orderResponse = restTemplate.getForObject(url, Map.class);
            if (orderResponse != null && orderResponse.containsKey("orders")) {
                @SuppressWarnings("unchecked")
                List<Map<String, Object>> returnedOrders = (List<Map<String, Object>>) orderResponse.get("orders");
                if (returnedOrders != null && !returnedOrders.isEmpty()) {
                    List<Map<String, Object>> returns = new ArrayList<>();
                    for (Map<String, Object> row : returnedOrders) {
                        Map<String, Object> ret = new LinkedHashMap<>();
                        String orderId = row.get("id") != null ? row.get("id").toString() : "unknown";
                        ret.put("id", "RET-" + orderId.substring(0, Math.min(8, orderId.length())));
                        ret.put("order_id", orderId);
                        ret.put("user_id", row.getOrDefault("user_id", "unknown").toString());
                        ret.put("product_name", row.getOrDefault("product_name", "상품").toString());
                        ret.put("status", "completed");
                        ret.put("status_display", "반품완료");
                        ret.put("refund_amount", row.getOrDefault("total_amount", 0));
                        ret.put("created_at", row.getOrDefault("created_at", "").toString());
                        returns.add(ret);
                    }

                    Map<String, Object> response = Map.of(
                        "returns", returns,
                        "total", returns.size()
                    );
                    return ResponseEntity.ok()
                        .header(HttpHeaders.ACCESS_CONTROL_ALLOW_ORIGIN, "*")
                        .body(response);
                }
            }
        } catch (Exception e) {
            logger.warn("Order service call failed, falling back to empty result: {}", e.getMessage());
        }

        // Empty fallback - no mock data
        List<Map<String, Object>> returns = List.of();

        Map<String, Object> response = Map.of(
            "returns", returns,
            "total", returns.size()
        );
        return ResponseEntity.ok()
            .header(HttpHeaders.ACCESS_CONTROL_ALLOW_ORIGIN, "*")
            .body(response);
    }

    @GetMapping("/api/v1/returns/{id}")
    public ResponseEntity<Map<String, Object>> getReturn(@PathVariable String id) {
        // No mock data - return not found for unknown IDs
        Map<String, Object> returnInfo = Map.of(
            "id", id,
            "error", "반품 정보를 찾을 수 없습니다",
            "status", "not_found"
        );
        return ResponseEntity.ok()
            .header(HttpHeaders.ACCESS_CONTROL_ALLOW_ORIGIN, "*")
            .body(returnInfo);
    }

    @GetMapping("/api/v1/returns/order/{orderId}")
    public ResponseEntity<Map<String, Object>> getReturnsByOrder(@PathVariable String orderId) {
        // In mock, we'll just return empty for the current orders since they haven't been returned
        List<Map<String, Object>> returns = List.of();

        Map<String, Object> response = Map.of(
            "order_id", orderId,
            "returns", returns,
            "total", returns.size(),
            "message", "해당 주문에 대한 반품 내역이 없습니다"
        );
        return ResponseEntity.ok()
            .header(HttpHeaders.ACCESS_CONTROL_ALLOW_ORIGIN, "*")
            .body(response);
    }

    @PutMapping("/api/v1/returns/{id}/approve")
    public ResponseEntity<Map<String, Object>> approveReturn(@PathVariable String id) {
        Map<String, Object> response = Map.of(
            "id", id,
            "status", "approved",
            "status_display", "반품승인",
            "refund_amount", 99990,
            "approved_at", "2026-03-20T12:00:00Z",
            "refund_status", "processing",
            "message", "반품이 승인되었습니다. 환불이 진행됩니다."
        );
        return ResponseEntity.ok()
            .header(HttpHeaders.ACCESS_CONTROL_ALLOW_ORIGIN, "*")
            .body(response);
    }
}
