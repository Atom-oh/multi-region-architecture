package com.mall.seller;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.HttpHeaders;
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.client.RestTemplate;

import java.util.HashMap;
import java.util.List;
import java.util.Map;

@RestController
@CrossOrigin(origins = "*", allowedHeaders = "*", methods = {RequestMethod.GET, RequestMethod.POST, RequestMethod.PUT, RequestMethod.DELETE, RequestMethod.OPTIONS})
public class Controller {

    @Autowired(required = false)
    private JdbcTemplate jdbcTemplate;

    private final RestTemplate restTemplate = new RestTemplate();

    private static final String PRODUCT_CATALOG_URL = "http://product-catalog.core-services.svc.cluster.local:80/api/v1/products";

    // Empty maps - no more mock seller data
    private static final Map<String, Map<String, Object>> SELLERS = new HashMap<>();
    private static final Map<String, List<Map<String, Object>>> SELLER_PRODUCTS = new HashMap<>();

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
    public ResponseEntity<Map<String, Object>> registerSeller(@RequestBody Map<String, Object> seller) {
        Map<String, Object> response = Map.ofEntries(
            Map.entry("id", "SEL-NEW-001"),
            Map.entry("business_name", seller.getOrDefault("business_name", "새로운 판매자")),
            Map.entry("business_number", seller.getOrDefault("business_number", "")),
            Map.entry("email", seller.getOrDefault("email", "seller@example.com")),
            Map.entry("phone", seller.getOrDefault("phone", "")),
            Map.entry("status", "PENDING_VERIFICATION"),
            Map.entry("status_display", "심사중"),
            Map.entry("created_at", "2026-03-20T10:00:00Z"),
            Map.entry("message", "판매자 등록 신청이 완료되었습니다. 영업일 기준 1-3일 내 심사 결과를 안내드립니다.")
        );
        return ResponseEntity.ok()
            .header(HttpHeaders.ACCESS_CONTROL_ALLOW_ORIGIN, "*")
            .body(response);
    }

    @GetMapping("/api/v1/sellers/{id}")
    public ResponseEntity<Map<String, Object>> getSeller(@PathVariable String id) {
        Map<String, Object> seller = SELLERS.get(id);

        if (seller != null) {
            return ResponseEntity.ok()
                .header(HttpHeaders.ACCESS_CONTROL_ALLOW_ORIGIN, "*")
                .body(seller);
        } else {
            return ResponseEntity.ok()
                .header(HttpHeaders.ACCESS_CONTROL_ALLOW_ORIGIN, "*")
                .body(Map.of(
                    "id", id,
                    "error", "판매자를 찾을 수 없습니다",
                    "status", "not_found"
                ));
        }
    }

    @GetMapping("/api/v1/sellers/{id}/products")
    public ResponseEntity<Map<String, Object>> getSellerProducts(@PathVariable String id) {
        // Try fetching products from product-catalog MSA
        List<Map<String, Object>> products = SELLER_PRODUCTS.getOrDefault(id, List.of());
        if (products.isEmpty()) {
            try {
                @SuppressWarnings("unchecked")
                Map<String, Object> catalogResponse = restTemplate.getForObject(
                    PRODUCT_CATALOG_URL + "?limit=20", Map.class);
                if (catalogResponse != null && catalogResponse.containsKey("products")) {
                    @SuppressWarnings("unchecked")
                    List<Map<String, Object>> catalogProducts = (List<Map<String, Object>>) catalogResponse.get("products");
                    if (catalogProducts != null && !catalogProducts.isEmpty()) {
                        Map<String, Object> seller = SELLERS.get(id);
                        Map<String, Object> response = Map.of(
                            "seller_id", id,
                            "seller_name", seller != null ? seller.get("business_name") : "Unknown",
                            "products", catalogProducts,
                            "total", catalogProducts.size()
                        );
                        return ResponseEntity.ok()
                            .header(HttpHeaders.ACCESS_CONTROL_ALLOW_ORIGIN, "*")
                            .body(response);
                    }
                }
            } catch (Exception e) {
                // Product catalog unavailable, return empty
            }
        }

        Map<String, Object> seller = SELLERS.get(id);
        Map<String, Object> response = Map.of(
            "seller_id", id,
            "seller_name", seller != null ? seller.get("business_name") : "Unknown",
            "products", products,
            "total", products.size()
        );
        return ResponseEntity.ok()
            .header(HttpHeaders.ACCESS_CONTROL_ALLOW_ORIGIN, "*")
            .body(response);
    }

    @PutMapping("/api/v1/sellers/{id}")
    public ResponseEntity<Map<String, Object>> updateSeller(@PathVariable String id, @RequestBody Map<String, Object> seller) {
        Map<String, Object> response = Map.of(
            "id", id,
            "business_name", seller.getOrDefault("business_name", "판매자"),
            "email", seller.getOrDefault("email", "seller@example.com"),
            "phone", seller.getOrDefault("phone", ""),
            "address", seller.getOrDefault("address", ""),
            "status", "VERIFIED",
            "updated_at", "2026-03-20T10:00:00Z",
            "message", "판매자 정보가 수정되었습니다"
        );
        return ResponseEntity.ok()
            .header(HttpHeaders.ACCESS_CONTROL_ALLOW_ORIGIN, "*")
            .body(response);
    }
}
