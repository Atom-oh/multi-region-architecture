package com.mall.pricing.dto;

public class PriceRequest {
    private String sku;

    public PriceRequest() {}

    public PriceRequest(String sku) {
        this.sku = sku;
    }

    public String getSku() {
        return sku;
    }

    public void setSku(String sku) {
        this.sku = sku;
    }
}
