package com.mall.seller;

import org.springframework.web.bind.annotation.*;
import java.util.List;
import java.util.Map;

@RestController
public class Controller {

    @GetMapping("/")
    public Map<String, Object> root() {
        return Map.of(
            "service", "seller-service",
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

    @PostMapping("/api/v1/sellers/register")
    public Map<String, Object> registerSeller(@RequestBody Map<String, Object> seller) {
        return Map.of(
            "id", "seller-001",
            "businessName", seller.getOrDefault("businessName", "Acme Store"),
            "email", seller.getOrDefault("email", "seller@example.com"),
            "status", "PENDING_VERIFICATION",
            "createdAt", "2026-03-20T10:00:00Z"
        );
    }

    @GetMapping("/api/v1/sellers/{id}")
    public Map<String, Object> getSeller(@PathVariable String id) {
        return Map.of(
            "id", id,
            "businessName", "Acme Store",
            "email", "seller@example.com",
            "phone", "+1-555-0123",
            "status", "ACTIVE",
            "rating", 4.8,
            "totalProducts", 156,
            "totalSales", 12500,
            "createdAt", "2025-06-15T08:00:00Z"
        );
    }

    @PutMapping("/api/v1/sellers/{id}")
    public Map<String, Object> updateSeller(@PathVariable String id, @RequestBody Map<String, Object> seller) {
        return Map.of(
            "id", id,
            "businessName", seller.getOrDefault("businessName", "Acme Store"),
            "email", seller.getOrDefault("email", "seller@example.com"),
            "phone", seller.getOrDefault("phone", "+1-555-0123"),
            "status", "ACTIVE",
            "updatedAt", "2026-03-20T10:00:00Z"
        );
    }
}
