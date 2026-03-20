package com.mall.returns;

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
            Map.entry("user_id", returnRequest.getOrDefault("user_id", "USR-001")),
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
    public ResponseEntity<Map<String, Object>> getReturns() {
        List<Map<String, Object>> returns = List.of(
            Map.ofEntries(
                Map.entry("id", "RET-001"),
                Map.entry("order_id", "ORD-OLD-001"),
                Map.entry("user_id", "USR-001"),
                Map.entry("user_name", "김민수"),
                Map.entry("status", "completed"),
                Map.entry("status_display", "반품완료"),
                Map.entry("reason", "상품불량"),
                Map.entry("refund_amount", 189000),
                Map.entry("created_at", "2026-03-10T14:00:00Z"),
                Map.entry("completed_at", "2026-03-15T10:00:00Z")
            ),
            Map.ofEntries(
                Map.entry("id", "RET-002"),
                Map.entry("order_id", "ORD-OLD-002"),
                Map.entry("user_id", "USR-002"),
                Map.entry("user_name", "이서연"),
                Map.entry("status", "approved"),
                Map.entry("status_display", "반품승인"),
                Map.entry("reason", "오배송"),
                Map.entry("refund_amount", 45000),
                Map.entry("created_at", "2026-03-18T09:00:00Z")
            )
        );

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
        Map<String, Object> returnInfo;
        switch (id) {
            case "RET-001":
                returnInfo = Map.ofEntries(
                    Map.entry("id", "RET-001"),
                    Map.entry("order_id", "ORD-OLD-001"),
                    Map.entry("user_id", "USR-001"),
                    Map.entry("user_name", "김민수"),
                    Map.entry("items", List.of(
                        Map.of("product_id", "PRD-002", "name", "나이키 에어맥스 97", "quantity", 1, "price", 189000, "reason", "상품불량 - 박음질 불량")
                    )),
                    Map.entry("status", "completed"),
                    Map.entry("status_display", "반품완료"),
                    Map.entry("reason", "상품불량"),
                    Map.entry("reason_detail", "신발 박음질이 뜯어져 있었습니다"),
                    Map.entry("refund_amount", 189000),
                    Map.entry("refund_method", "원결제수단"),
                    Map.entry("pickup_address", Map.of(
                        "name", "김민수",
                        "phone", "010-1234-5678",
                        "address", "서울특별시 강남구 테헤란로 123 멀티리전타워 15층"
                    )),
                    Map.entry("created_at", "2026-03-10T14:00:00Z"),
                    Map.entry("pickup_completed_at", "2026-03-12T11:30:00Z"),
                    Map.entry("completed_at", "2026-03-15T10:00:00Z")
                );
                break;
            case "RET-002":
                returnInfo = Map.ofEntries(
                    Map.entry("id", "RET-002"),
                    Map.entry("order_id", "ORD-OLD-002"),
                    Map.entry("user_id", "USR-002"),
                    Map.entry("user_name", "이서연"),
                    Map.entry("items", List.of(
                        Map.of("product_id", "PRD-009", "name", "스타벅스 텀블러 세트", "quantity", 1, "price", 45000, "reason", "오배송 - 다른 상품 배송됨")
                    )),
                    Map.entry("status", "approved"),
                    Map.entry("status_display", "반품승인"),
                    Map.entry("reason", "오배송"),
                    Map.entry("reason_detail", "주문한 것과 다른 색상의 상품이 배송되었습니다"),
                    Map.entry("refund_amount", 45000),
                    Map.entry("refund_method", "원결제수단"),
                    Map.entry("pickup_address", Map.of(
                        "name", "이서연",
                        "phone", "010-9876-5432",
                        "address", "서울특별시 서초구 강남대로 456 힐스테이트 1203호"
                    )),
                    Map.entry("created_at", "2026-03-18T09:00:00Z"),
                    Map.entry("approved_at", "2026-03-18T14:00:00Z"),
                    Map.entry("pickup_scheduled", "2026-03-21T10:00:00Z")
                );
                break;
            default:
                returnInfo = Map.of(
                    "id", id,
                    "error", "반품 정보를 찾을 수 없습니다",
                    "status", "not_found"
                );
        }
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
