package com.mall.returns;

import org.springframework.web.bind.annotation.*;
import java.util.List;
import java.util.Map;

@RestController
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
    public Map<String, Object> createReturn(@RequestBody Map<String, Object> returnRequest) {
        return Map.of(
            "id", "ret-22222",
            "orderId", returnRequest.getOrDefault("orderId", "ord-12345"),
            "reason", returnRequest.getOrDefault("reason", "Defective product"),
            "status", "PENDING",
            "createdAt", "2026-03-20T10:00:00Z"
        );
    }

    @GetMapping("/api/v1/returns")
    public List<Map<String, Object>> getReturns() {
        return List.of(
            Map.of("id", "ret-22222", "orderId", "ord-12345", "status", "PENDING", "reason", "Defective product"),
            Map.of("id", "ret-22223", "orderId", "ord-12346", "status", "APPROVED", "reason", "Wrong size")
        );
    }

    @GetMapping("/api/v1/returns/{id}")
    public Map<String, Object> getReturn(@PathVariable String id) {
        return Map.of(
            "id", id,
            "orderId", "ord-12345",
            "items", List.of(
                Map.of("productId", "prod-001", "quantity", 1, "reason", "Defective")
            ),
            "status", "PENDING",
            "refundAmount", 99.99,
            "createdAt", "2026-03-20T10:00:00Z"
        );
    }

    @PutMapping("/api/v1/returns/{id}/approve")
    public Map<String, Object> approveReturn(@PathVariable String id) {
        return Map.of(
            "id", id,
            "status", "APPROVED",
            "refundAmount", 99.99,
            "approvedAt", "2026-03-20T12:00:00Z",
            "refundStatus", "PROCESSING"
        );
    }
}
