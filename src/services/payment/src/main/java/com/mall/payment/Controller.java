package com.mall.payment;

import org.springframework.web.bind.annotation.*;
import java.util.List;
import java.util.Map;

@RestController
public class Controller {

    @GetMapping("/")
    public Map<String, Object> root() {
        return Map.of(
            "service", "payment-service",
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

    @PostMapping("/api/v1/payments")
    public Map<String, Object> createPayment(@RequestBody Map<String, Object> payment) {
        return Map.of(
            "id", "pay-67890",
            "orderId", payment.getOrDefault("orderId", "ord-12345"),
            "amount", payment.getOrDefault("amount", 299.99),
            "method", payment.getOrDefault("method", "CREDIT_CARD"),
            "status", "COMPLETED",
            "transactionId", "txn-abc123def456",
            "createdAt", "2026-03-20T10:05:00Z"
        );
    }

    @GetMapping("/api/v1/payments")
    public List<Map<String, Object>> getPayments() {
        return List.of(
            Map.of("id", "pay-67890", "orderId", "ord-12345", "amount", 299.99, "status", "COMPLETED"),
            Map.of("id", "pay-67891", "orderId", "ord-12346", "amount", 149.50, "status", "PENDING")
        );
    }

    @GetMapping("/api/v1/payments/{id}")
    public Map<String, Object> getPayment(@PathVariable String id) {
        return Map.of(
            "id", id,
            "orderId", "ord-12345",
            "amount", 299.99,
            "method", "CREDIT_CARD",
            "status", "COMPLETED",
            "transactionId", "txn-abc123def456",
            "createdAt", "2026-03-20T10:05:00Z"
        );
    }

    @PostMapping("/api/v1/payments/{id}/refund")
    public Map<String, Object> refundPayment(@PathVariable String id) {
        return Map.of(
            "id", id,
            "refundId", "ref-11111",
            "amount", 299.99,
            "status", "REFUNDED",
            "refundedAt", "2026-03-20T12:00:00Z"
        );
    }
}
