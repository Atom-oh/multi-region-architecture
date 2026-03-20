package com.mall.pricing;

import org.springframework.web.bind.annotation.*;
import java.util.List;
import java.util.Map;

@RestController
public class Controller {

    @GetMapping("/")
    public Map<String, Object> root() {
        return Map.of(
            "service", "pricing-service",
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

    @GetMapping("/api/v1/prices/{productId}")
    public Map<String, Object> getPrice(@PathVariable String productId) {
        return Map.of(
            "productId", productId,
            "basePrice", 99.99,
            "currency", "USD",
            "discount", 10.0,
            "finalPrice", 89.99,
            "validUntil", "2026-03-31T23:59:59Z"
        );
    }

    @PutMapping("/api/v1/prices/{productId}")
    public Map<String, Object> updatePrice(@PathVariable String productId, @RequestBody Map<String, Object> priceUpdate) {
        return Map.of(
            "productId", productId,
            "basePrice", priceUpdate.getOrDefault("basePrice", 99.99),
            "currency", priceUpdate.getOrDefault("currency", "USD"),
            "discount", priceUpdate.getOrDefault("discount", 0.0),
            "updatedAt", "2026-03-20T10:00:00Z"
        );
    }

    @GetMapping("/api/v1/prices/bulk")
    public List<Map<String, Object>> getBulkPrices(@RequestParam(required = false) List<String> productIds) {
        return List.of(
            Map.of("productId", "prod-001", "basePrice", 99.99, "finalPrice", 89.99, "currency", "USD"),
            Map.of("productId", "prod-002", "basePrice", 149.99, "finalPrice", 134.99, "currency", "USD"),
            Map.of("productId", "prod-003", "basePrice", 29.99, "finalPrice", 29.99, "currency", "USD")
        );
    }
}
