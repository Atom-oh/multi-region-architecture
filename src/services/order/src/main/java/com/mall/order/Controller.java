package com.mall.order;

import org.springframework.http.HttpHeaders;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;
import java.util.List;
import java.util.Map;

@RestController
@CrossOrigin(origins = "*", allowedHeaders = "*", methods = {RequestMethod.GET, RequestMethod.POST, RequestMethod.PUT, RequestMethod.DELETE, RequestMethod.OPTIONS})
public class Controller {

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
    public ResponseEntity<Map<String, Object>> createOrder(@RequestBody Map<String, Object> order) {
        Map<String, Object> response = Map.of(
            "id", "ORD-NEW-001",
            "user_id", order.getOrDefault("user_id", "USR-001"),
            "items", order.getOrDefault("items", List.of()),
            "total_amount", order.getOrDefault("total_amount", 0),
            "currency", "KRW",
            "status", "pending",
            "status_display", "주문접수",
            "created_at", "2026-03-20T10:00:00Z",
            "message", "주문이 접수되었습니다"
        );
        return ResponseEntity.ok()
            .header(HttpHeaders.ACCESS_CONTROL_ALLOW_ORIGIN, "*")
            .body(response);
    }

    @GetMapping("/api/v1/orders")
    public ResponseEntity<List<Map<String, Object>>> getOrders() {
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
}
