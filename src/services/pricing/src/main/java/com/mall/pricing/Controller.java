package com.mall.pricing;

import org.springframework.http.HttpHeaders;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;
import java.util.List;
import java.util.Map;

@RestController
@CrossOrigin(origins = "*", allowedHeaders = "*", methods = {RequestMethod.GET, RequestMethod.POST, RequestMethod.PUT, RequestMethod.DELETE, RequestMethod.OPTIONS})
public class Controller {

    // Mock pricing data - consistent with shared product IDs
    private static final Map<String, Map<String, Object>> PRODUCT_PRICES = Map.ofEntries(
        Map.entry("PRD-001", Map.of("name", "삼성 갤럭시 S25 울트라", "base_price", 1990000, "current_price", 1890000, "discount_percent", 5, "discount_amount", 100000)),
        Map.entry("PRD-002", Map.of("name", "나이키 에어맥스 97", "base_price", 219000, "current_price", 189000, "discount_percent", 14, "discount_amount", 30000)),
        Map.entry("PRD-003", Map.of("name", "다이슨 에어랩", "base_price", 699000, "current_price", 699000, "discount_percent", 0, "discount_amount", 0)),
        Map.entry("PRD-004", Map.of("name", "애플 맥북 프로 M4", "base_price", 2990000, "current_price", 2990000, "discount_percent", 0, "discount_amount", 0)),
        Map.entry("PRD-005", Map.of("name", "르크루제 냄비 세트", "base_price", 550000, "current_price", 459000, "discount_percent", 17, "discount_amount", 91000)),
        Map.entry("PRD-006", Map.of("name", "아디다스 울트라부스트", "base_price", 239000, "current_price", 219000, "discount_percent", 8, "discount_amount", 20000)),
        Map.entry("PRD-007", Map.of("name", "LG 올레드 TV 65\"", "base_price", 3590000, "current_price", 3290000, "discount_percent", 8, "discount_amount", 300000)),
        Map.entry("PRD-008", Map.of("name", "무지 캔버스 토트백", "base_price", 35000, "current_price", 29000, "discount_percent", 17, "discount_amount", 6000)),
        Map.entry("PRD-009", Map.of("name", "스타벅스 텀블러 세트", "base_price", 52000, "current_price", 45000, "discount_percent", 13, "discount_amount", 7000)),
        Map.entry("PRD-010", Map.of("name", "소니 WH-1000XM5", "base_price", 459000, "current_price", 429000, "discount_percent", 7, "discount_amount", 30000))
    );

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
    public ResponseEntity<Map<String, Object>> getPrice(@PathVariable String productId) {
        Map<String, Object> priceData = PRODUCT_PRICES.get(productId);

        Map<String, Object> response;
        if (priceData != null) {
            response = Map.ofEntries(
                Map.entry("product_id", productId),
                Map.entry("name", priceData.get("name")),
                Map.entry("base_price", priceData.get("base_price")),
                Map.entry("current_price", priceData.get("current_price")),
                Map.entry("discount_percent", priceData.get("discount_percent")),
                Map.entry("discount_amount", priceData.get("discount_amount")),
                Map.entry("currency", "KRW"),
                Map.entry("valid_until", "2026-03-31T23:59:59Z"),
                Map.entry("promotions", List.of())
            );
        } else {
            response = Map.of(
                "product_id", productId,
                "error", "상품 가격 정보를 찾을 수 없습니다",
                "status", "not_found"
            );
        }
        return ResponseEntity.ok()
            .header(HttpHeaders.ACCESS_CONTROL_ALLOW_ORIGIN, "*")
            .body(response);
    }

    @PutMapping("/api/v1/prices/{productId}")
    public ResponseEntity<Map<String, Object>> updatePrice(@PathVariable String productId, @RequestBody Map<String, Object> priceUpdate) {
        Map<String, Object> response = Map.of(
            "product_id", productId,
            "base_price", priceUpdate.getOrDefault("base_price", 99990),
            "current_price", priceUpdate.getOrDefault("current_price", 99990),
            "discount_percent", priceUpdate.getOrDefault("discount_percent", 0),
            "currency", "KRW",
            "updated_at", "2026-03-20T10:00:00Z",
            "message", "가격이 업데이트되었습니다"
        );
        return ResponseEntity.ok()
            .header(HttpHeaders.ACCESS_CONTROL_ALLOW_ORIGIN, "*")
            .body(response);
    }

    @GetMapping("/api/v1/prices/bulk")
    public ResponseEntity<Map<String, Object>> getBulkPrices(@RequestParam(required = false) List<String> productIds) {
        List<Map<String, Object>> prices = PRODUCT_PRICES.entrySet().stream()
            .filter(e -> productIds == null || productIds.isEmpty() || productIds.contains(e.getKey()))
            .map(e -> Map.of(
                "product_id", e.getKey(),
                "name", e.getValue().get("name"),
                "base_price", e.getValue().get("base_price"),
                "current_price", e.getValue().get("current_price"),
                "discount_percent", e.getValue().get("discount_percent"),
                "currency", "KRW"
            ))
            .toList();

        Map<String, Object> response = Map.of(
            "prices", prices,
            "total", prices.size(),
            "currency", "KRW"
        );
        return ResponseEntity.ok()
            .header(HttpHeaders.ACCESS_CONTROL_ALLOW_ORIGIN, "*")
            .body(response);
    }

    @PostMapping("/api/v1/prices/calculate")
    public ResponseEntity<Map<String, Object>> calculatePrice(@RequestBody Map<String, Object> request) {
        @SuppressWarnings("unchecked")
        List<Map<String, Object>> items = (List<Map<String, Object>>) request.getOrDefault("items", List.of());
        String couponCode = (String) request.getOrDefault("coupon_code", null);
        String membershipTier = (String) request.getOrDefault("membership_tier", "BRONZE");

        int subtotal = 0;
        int totalDiscount = 0;

        List<Map<String, Object>> calculatedItems = new java.util.ArrayList<>();
        for (Map<String, Object> item : items) {
            String productId = (String) item.get("product_id");
            int quantity = ((Number) item.getOrDefault("quantity", 1)).intValue();

            Map<String, Object> priceData = PRODUCT_PRICES.get(productId);
            if (priceData != null) {
                int basePrice = ((Number) priceData.get("base_price")).intValue();
                int currentPrice = ((Number) priceData.get("current_price")).intValue();
                int itemSubtotal = currentPrice * quantity;
                int itemDiscount = (basePrice - currentPrice) * quantity;

                subtotal += itemSubtotal;
                totalDiscount += itemDiscount;

                calculatedItems.add(Map.of(
                    "product_id", productId,
                    "name", priceData.get("name"),
                    "quantity", quantity,
                    "unit_price", currentPrice,
                    "subtotal", itemSubtotal,
                    "discount", itemDiscount
                ));
            }
        }

        // Apply membership discount
        int membershipDiscount = 0;
        switch (membershipTier) {
            case "PLATINUM": membershipDiscount = (int)(subtotal * 0.05); break;
            case "GOLD": membershipDiscount = (int)(subtotal * 0.03); break;
            case "SILVER": membershipDiscount = (int)(subtotal * 0.01); break;
        }

        // Apply coupon discount
        int couponDiscount = 0;
        String couponMessage = null;
        if (couponCode != null && couponCode.equals("WELCOME10")) {
            couponDiscount = (int)(subtotal * 0.10);
            couponMessage = "신규 회원 10% 할인 적용";
        }

        int shippingFee = subtotal >= 50000 ? 0 : 3000;
        int finalPrice = subtotal - membershipDiscount - couponDiscount + shippingFee;

        Map<String, Object> response = new java.util.HashMap<>();
        response.put("items", calculatedItems);
        response.put("subtotal", subtotal);
        response.put("product_discount", totalDiscount);
        response.put("membership_discount", membershipDiscount);
        response.put("membership_tier", membershipTier);
        response.put("coupon_discount", couponDiscount);
        response.put("coupon_code", couponCode);
        response.put("coupon_message", couponMessage);
        response.put("shipping_fee", shippingFee);
        response.put("shipping_message", shippingFee == 0 ? "무료배송" : "50,000원 이상 구매시 무료배송");
        response.put("total_discount", totalDiscount + membershipDiscount + couponDiscount);
        response.put("final_price", finalPrice);
        response.put("currency", "KRW");
        return ResponseEntity.ok()
            .header(HttpHeaders.ACCESS_CONTROL_ALLOW_ORIGIN, "*")
            .body(response);
    }
}
