package com.mall.pricing.controller;

import java.util.List;

import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import com.mall.pricing.dto.CalculateRequest;
import com.mall.pricing.dto.CalculateResponse;
import com.mall.pricing.dto.PriceResponse;
import com.mall.pricing.model.Promotion;
import com.mall.pricing.service.PricingService;

@RestController
@RequestMapping("/api/v1")
public class PricingController {

    private final PricingService pricingService;

    public PricingController(PricingService pricingService) {
        this.pricingService = pricingService;
    }

    @GetMapping("/pricing/{sku}")
    public ResponseEntity<PriceResponse> getPrice(@PathVariable String sku) {
        return pricingService.getPriceBySku(sku)
                .map(ResponseEntity::ok)
                .orElse(ResponseEntity.notFound().build());
    }

    @PostMapping("/pricing/calculate")
    public ResponseEntity<CalculateResponse> calculatePrice(@RequestBody CalculateRequest request) {
        CalculateResponse response = pricingService.calculateCartPrice(request);
        return ResponseEntity.ok(response);
    }

    @GetMapping("/promotions")
    public ResponseEntity<List<Promotion>> getActivePromotions() {
        List<Promotion> promotions = pricingService.getActivePromotions();
        return ResponseEntity.ok(promotions);
    }

    @PostMapping("/promotions")
    public ResponseEntity<Promotion> createPromotion(@RequestBody Promotion promotion) {
        Promotion created = pricingService.createPromotion(promotion);
        return ResponseEntity.status(201).body(created);
    }
}
