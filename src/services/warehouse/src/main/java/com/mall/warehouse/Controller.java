package com.mall.warehouse;

import org.springframework.web.bind.annotation.*;
import java.util.List;
import java.util.Map;

@RestController
public class Controller {

    @GetMapping("/")
    public Map<String, Object> root() {
        return Map.of(
            "service", "warehouse-service",
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

    @GetMapping("/api/v1/warehouses")
    public List<Map<String, Object>> getWarehouses() {
        return List.of(
            Map.of("id", "wh-001", "name", "East Coast Warehouse", "location", "New Jersey", "capacity", 50000),
            Map.of("id", "wh-002", "name", "West Coast Warehouse", "location", "California", "capacity", 75000)
        );
    }

    @GetMapping("/api/v1/warehouses/{id}/stock")
    public Map<String, Object> getStock(@PathVariable String id) {
        return Map.of(
            "warehouseId", id,
            "items", List.of(
                Map.of("productId", "prod-001", "quantity", 500, "reserved", 50),
                Map.of("productId", "prod-002", "quantity", 1200, "reserved", 100),
                Map.of("productId", "prod-003", "quantity", 300, "reserved", 25)
            ),
            "lastUpdated", "2026-03-20T09:00:00Z"
        );
    }

    @PutMapping("/api/v1/warehouses/{id}/stock")
    public Map<String, Object> updateStock(@PathVariable String id, @RequestBody Map<String, Object> stockUpdate) {
        return Map.of(
            "warehouseId", id,
            "productId", stockUpdate.getOrDefault("productId", "prod-001"),
            "previousQuantity", 500,
            "newQuantity", stockUpdate.getOrDefault("quantity", 450),
            "updatedAt", "2026-03-20T10:00:00Z"
        );
    }
}
