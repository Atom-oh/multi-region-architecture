package com.mall.order;

import org.springframework.web.bind.annotation.*;
import java.util.List;
import java.util.Map;

@RestController
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
    public Map<String, Object> createOrder(@RequestBody Map<String, Object> order) {
        return Map.of(
            "id", "ord-12345",
            "userId", order.getOrDefault("userId", "user-001"),
            "items", order.getOrDefault("items", List.of()),
            "totalAmount", 299.99,
            "status", "PENDING",
            "createdAt", "2026-03-20T10:00:00Z"
        );
    }

    @GetMapping("/api/v1/orders")
    public List<Map<String, Object>> getOrders() {
        return List.of(
            Map.of("id", "ord-12345", "userId", "user-001", "totalAmount", 299.99, "status", "COMPLETED"),
            Map.of("id", "ord-12346", "userId", "user-002", "totalAmount", 149.50, "status", "PENDING")
        );
    }

    @GetMapping("/api/v1/orders/{id}")
    public Map<String, Object> getOrder(@PathVariable String id) {
        return Map.of(
            "id", id,
            "userId", "user-001",
            "items", List.of(
                Map.of("productId", "prod-001", "quantity", 2, "price", 99.99),
                Map.of("productId", "prod-002", "quantity", 1, "price", 100.01)
            ),
            "totalAmount", 299.99,
            "status", "COMPLETED",
            "createdAt", "2026-03-20T10:00:00Z"
        );
    }

    @GetMapping("/api/v1/orders/user/{userId}")
    public List<Map<String, Object>> getOrdersByUser(@PathVariable String userId) {
        return List.of(
            Map.of("id", "ord-12345", "userId", userId, "totalAmount", 299.99, "status", "COMPLETED"),
            Map.of("id", "ord-12350", "userId", userId, "totalAmount", 75.00, "status", "PENDING")
        );
    }
}
