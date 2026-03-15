package com.mall.pricing.dto;

import java.math.BigDecimal;
import java.util.UUID;

public class PriceResponse {
    private UUID id;
    private String sku;
    private BigDecimal basePrice;
    private BigDecimal finalPrice;
    private String currency;
    private BigDecimal discountApplied;

    public PriceResponse() {}

    public PriceResponse(UUID id, String sku, BigDecimal basePrice, BigDecimal finalPrice, String currency, BigDecimal discountApplied) {
        this.id = id;
        this.sku = sku;
        this.basePrice = basePrice;
        this.finalPrice = finalPrice;
        this.currency = currency;
        this.discountApplied = discountApplied;
    }

    public UUID getId() {
        return id;
    }

    public void setId(UUID id) {
        this.id = id;
    }

    public String getSku() {
        return sku;
    }

    public void setSku(String sku) {
        this.sku = sku;
    }

    public BigDecimal getBasePrice() {
        return basePrice;
    }

    public void setBasePrice(BigDecimal basePrice) {
        this.basePrice = basePrice;
    }

    public BigDecimal getFinalPrice() {
        return finalPrice;
    }

    public void setFinalPrice(BigDecimal finalPrice) {
        this.finalPrice = finalPrice;
    }

    public String getCurrency() {
        return currency;
    }

    public void setCurrency(String currency) {
        this.currency = currency;
    }

    public BigDecimal getDiscountApplied() {
        return discountApplied;
    }

    public void setDiscountApplied(BigDecimal discountApplied) {
        this.discountApplied = discountApplied;
    }
}
