package com.mall.seller;

import org.springframework.http.HttpHeaders;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;
import java.util.List;
import java.util.Map;

@RestController
@CrossOrigin(origins = "*", allowedHeaders = "*", methods = {RequestMethod.GET, RequestMethod.POST, RequestMethod.PUT, RequestMethod.DELETE, RequestMethod.OPTIONS})
public class Controller {

    // Mock seller data - consistent with shared seller IDs
    private static final Map<String, Map<String, Object>> SELLERS = Map.ofEntries(
        Map.entry("SEL-001", Map.ofEntries(
            Map.entry("id", "SEL-001"),
            Map.entry("business_name", "삼성전자 Official"),
            Map.entry("business_number", "124-81-00998"),
            Map.entry("email", "official@samsung.com"),
            Map.entry("phone", "1588-3366"),
            Map.entry("address", "경기도 수원시 영통구 삼성로 129"),
            Map.entry("status", "VERIFIED"),
            Map.entry("status_display", "인증완료"),
            Map.entry("rating", 4.9),
            Map.entry("review_count", 15234),
            Map.entry("total_products", 1523),
            Map.entry("total_sales", 89234000000L),
            Map.entry("joined_at", "2020-01-15T00:00:00Z"),
            Map.entry("badge", List.of("공식판매자", "프리미엄", "빠른배송"))
        )),
        Map.entry("SEL-002", Map.ofEntries(
            Map.entry("id", "SEL-002"),
            Map.entry("business_name", "Nike Korea"),
            Map.entry("business_number", "211-86-15432"),
            Map.entry("email", "official@nike.co.kr"),
            Map.entry("phone", "080-022-0182"),
            Map.entry("address", "서울특별시 강남구 테헤란로 152"),
            Map.entry("status", "VERIFIED"),
            Map.entry("status_display", "인증완료"),
            Map.entry("rating", 4.7),
            Map.entry("review_count", 8921),
            Map.entry("total_products", 892),
            Map.entry("total_sales", 23456000000L),
            Map.entry("joined_at", "2019-06-20T00:00:00Z"),
            Map.entry("badge", List.of("공식판매자", "빠른배송"))
        )),
        Map.entry("SEL-003", Map.ofEntries(
            Map.entry("id", "SEL-003"),
            Map.entry("business_name", "Dyson Korea"),
            Map.entry("business_number", "120-81-54321"),
            Map.entry("email", "official@dyson.co.kr"),
            Map.entry("phone", "1588-4253"),
            Map.entry("address", "서울특별시 강남구 영동대로 517"),
            Map.entry("status", "VERIFIED"),
            Map.entry("status_display", "인증완료"),
            Map.entry("rating", 4.8),
            Map.entry("review_count", 12543),
            Map.entry("total_products", 156),
            Map.entry("total_sales", 45678000000L),
            Map.entry("joined_at", "2018-03-10T00:00:00Z"),
            Map.entry("badge", List.of("공식판매자", "프리미엄", "무료배송"))
        ))
    );

    // Product mapping to sellers
    private static final Map<String, List<Map<String, Object>>> SELLER_PRODUCTS = Map.of(
        "SEL-001", List.of(
            Map.of("product_id", "PRD-001", "name", "삼성 갤럭시 S25 울트라", "price", 1890000, "stock", 150, "sales", 4521, "rating", 4.8),
            Map.of("product_id", "PRD-007", "name", "LG 올레드 TV 65\"", "price", 3290000, "stock", 35, "sales", 2150, "rating", 4.8)
        ),
        "SEL-002", List.of(
            Map.of("product_id", "PRD-002", "name", "나이키 에어맥스 97", "price", 189000, "stock", 89, "sales", 1892, "rating", 4.6)
        ),
        "SEL-003", List.of(
            Map.of("product_id", "PRD-003", "name", "다이슨 에어랩", "price", 699000, "stock", 45, "sales", 3210, "rating", 4.9)
        )
    );

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
        List<Map<String, Object>> products = SELLER_PRODUCTS.getOrDefault(id, List.of());
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
