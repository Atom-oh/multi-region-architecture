package com.mall.pricing;

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

    // Empty map - no more mock pricing data. Prices come from product-catalog MSA.
    private static final Map<String, Map<String, Object>> PRODUCT_PRICES = new HashMap<>();

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
        // Try fetching price from product-catalog MSA
        try {
            @SuppressWarnings("unchecked")
            Map<String, Object> product = restTemplate.getForObject(
                PRODUCT_CATALOG_URL + "/" + productId, Map.class);
            if (product != null && product.containsKey("price")) {
                Number price = (Number) product.get("price");
                int basePrice = price.intValue();
                int currentPrice = basePrice;
                // Check if product has a discount price
                if (product.containsKey("discount_price") && product.get("discount_price") != null) {
                    currentPrice = ((Number) product.get("discount_price")).intValue();
                }
                int discountAmount = basePrice - currentPrice;
                int discountPercent = basePrice > 0 ? (discountAmount * 100) / basePrice : 0;

                Map<String, Object> response = Map.ofEntries(
                    Map.entry("product_id", productId),
                    Map.entry("name", product.getOrDefault("name", "")),
                    Map.entry("base_price", basePrice),
                    Map.entry("current_price", currentPrice),
                    Map.entry("discount_percent", discountPercent),
                    Map.entry("discount_amount", discountAmount),
                    Map.entry("currency", "KRW"),
                    Map.entry("valid_until", "2026-12-31T23:59:59Z"),
                    Map.entry("promotions", List.of())
                );
                return ResponseEntity.ok()
                    .header(HttpHeaders.ACCESS_CONTROL_ALLOW_ORIGIN, "*")
                    .body(response);
            }
        } catch (Exception e) {
            // Product catalog unavailable, fall through to not found
        }

        // Check local cache (empty by default, could be populated by future DB integration)
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
                Map.entry("valid_until", "2026-12-31T23:59:59Z"),
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

            // Try product-catalog MSA first, then local cache
            Map<String, Object> priceData = PRODUCT_PRICES.get(productId);
            if (priceData == null) {
                try {
                    @SuppressWarnings("unchecked")
                    Map<String, Object> product = restTemplate.getForObject(
                        PRODUCT_CATALOG_URL + "/" + productId, Map.class);
                    if (product != null && product.containsKey("price")) {
                        Number price = (Number) product.get("price");
                        int basePrice = price.intValue();
                        int currentPrice = basePrice;
                        if (product.containsKey("discount_price") && product.get("discount_price") != null) {
                            currentPrice = ((Number) product.get("discount_price")).intValue();
                        }
                        priceData = Map.of(
                            "name", product.getOrDefault("name", ""),
                            "base_price", basePrice,
                            "current_price", currentPrice
                        );
                    }
                } catch (Exception e) {
                    // Product catalog unavailable, skip this item
                }
            }

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
