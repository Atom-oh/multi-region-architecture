package com.mall.warehouse;

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
    public ResponseEntity<Map<String, Object>> getWarehouses() {
        List<Map<String, Object>> warehouses = List.of(
            Map.ofEntries(
                Map.entry("id", "WH-SEOUL-001"),
                Map.entry("name", "서울 강남 물류센터"),
                Map.entry("location", Map.of(
                    "city", "서울특별시",
                    "district", "강남구",
                    "address", "테헤란로 123",
                    "zip", "06234"
                )),
                Map.entry("capacity", 50000),
                Map.entry("current_usage", 42350),
                Map.entry("usage_rate", 84.7),
                Map.entry("status", "operational"),
                Map.entry("status_display", "운영중"),
                Map.entry("contact", "02-1234-5678")
            ),
            Map.ofEntries(
                Map.entry("id", "WH-SEOUL-002"),
                Map.entry("name", "서울 송파 물류센터"),
                Map.entry("location", Map.of(
                    "city", "서울특별시",
                    "district", "송파구",
                    "address", "올림픽로 300",
                    "zip", "05551"
                )),
                Map.entry("capacity", 35000),
                Map.entry("current_usage", 28750),
                Map.entry("usage_rate", 82.1),
                Map.entry("status", "operational"),
                Map.entry("status_display", "운영중"),
                Map.entry("contact", "02-2345-6789")
            ),
            Map.ofEntries(
                Map.entry("id", "WH-BUSAN-001"),
                Map.entry("name", "부산 해운대 물류센터"),
                Map.entry("location", Map.of(
                    "city", "부산광역시",
                    "district", "해운대구",
                    "address", "센텀로 100",
                    "zip", "48058"
                )),
                Map.entry("capacity", 75000),
                Map.entry("current_usage", 51200),
                Map.entry("usage_rate", 68.3),
                Map.entry("status", "operational"),
                Map.entry("status_display", "운영중"),
                Map.entry("contact", "051-1234-5678")
            )
        );

        Map<String, Object> response = Map.of(
            "warehouses", warehouses,
            "total", warehouses.size(),
            "total_capacity", 160000,
            "total_usage", 122300,
            "overall_usage_rate", 76.4
        );
        return ResponseEntity.ok()
            .header(HttpHeaders.ACCESS_CONTROL_ALLOW_ORIGIN, "*")
            .body(response);
    }

    @GetMapping("/api/v1/warehouses/{id}/stock")
    public ResponseEntity<Map<String, Object>> getStock(@PathVariable String id) {
        List<Map<String, Object>> items;
        String warehouseName;

        switch (id) {
            case "WH-SEOUL-001":
                warehouseName = "서울 강남 물류센터";
                items = List.of(
                    Map.of("product_id", "PRD-001", "name", "삼성 갤럭시 S25 울트라", "quantity", 150, "reserved", 23, "available", 127, "location", "A-1-01"),
                    Map.of("product_id", "PRD-002", "name", "나이키 에어맥스 97", "quantity", 89, "reserved", 12, "available", 77, "location", "B-2-15"),
                    Map.of("product_id", "PRD-004", "name", "애플 맥북 프로 M4", "quantity", 72, "reserved", 15, "available", 57, "location", "A-1-03"),
                    Map.of("product_id", "PRD-006", "name", "아디다스 울트라부스트", "quantity", 200, "reserved", 30, "available", 170, "location", "B-3-08"),
                    Map.of("product_id", "PRD-009", "name", "스타벅스 텀블러 세트", "quantity", 300, "reserved", 22, "available", 278, "location", "C-1-22")
                );
                break;
            case "WH-SEOUL-002":
                warehouseName = "서울 송파 물류센터";
                items = List.of(
                    Map.of("product_id", "PRD-007", "name", "LG 올레드 TV 65\"", "quantity", 35, "reserved", 7, "available", 28, "location", "A-2-01"),
                    Map.of("product_id", "PRD-010", "name", "소니 WH-1000XM5", "quantity", 85, "reserved", 18, "available", 67, "location", "B-1-05")
                );
                break;
            case "WH-BUSAN-001":
                warehouseName = "부산 해운대 물류센터";
                items = List.of(
                    Map.of("product_id", "PRD-003", "name", "다이슨 에어랩", "quantity", 45, "reserved", 8, "available", 37, "location", "A-1-12"),
                    Map.of("product_id", "PRD-005", "name", "르크루제 냄비 세트", "quantity", 120, "reserved", 5, "available", 115, "location", "C-2-08"),
                    Map.of("product_id", "PRD-008", "name", "무지 캔버스 토트백", "quantity", 500, "reserved", 45, "available", 455, "location", "D-1-01")
                );
                break;
            default:
                return ResponseEntity.ok()
                    .header(HttpHeaders.ACCESS_CONTROL_ALLOW_ORIGIN, "*")
                    .body(Map.of("error", "창고를 찾을 수 없습니다", "warehouse_id", id));
        }

        Map<String, Object> response = Map.of(
            "warehouse_id", id,
            "warehouse_name", warehouseName,
            "items", items,
            "total_items", items.size(),
            "last_updated", "2026-03-20T09:00:00Z"
        );
        return ResponseEntity.ok()
            .header(HttpHeaders.ACCESS_CONTROL_ALLOW_ORIGIN, "*")
            .body(response);
    }

    @PutMapping("/api/v1/warehouses/{id}/stock")
    public ResponseEntity<Map<String, Object>> updateStock(@PathVariable String id, @RequestBody Map<String, Object> stockUpdate) {
        Map<String, Object> response = Map.of(
            "warehouse_id", id,
            "product_id", stockUpdate.getOrDefault("product_id", "PRD-001"),
            "previous_quantity", 500,
            "new_quantity", stockUpdate.getOrDefault("quantity", 450),
            "operation", stockUpdate.getOrDefault("operation", "set"),
            "updated_at", "2026-03-20T10:00:00Z",
            "message", "재고가 업데이트되었습니다"
        );
        return ResponseEntity.ok()
            .header(HttpHeaders.ACCESS_CONTROL_ALLOW_ORIGIN, "*")
            .body(response);
    }
}
