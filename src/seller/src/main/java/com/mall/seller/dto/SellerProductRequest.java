package com.mall.seller.dto;

import java.math.BigDecimal;

public class SellerProductRequest {
    private String productId;
    private String sku;
    private BigDecimal price;
    private Integer stock;

    public SellerProductRequest() {}

    public SellerProductRequest(String productId, String sku, BigDecimal price, Integer stock) {
        this.productId = productId;
        this.sku = sku;
        this.price = price;
        this.stock = stock;
    }

    public String getProductId() {
        return productId;
    }

    public void setProductId(String productId) {
        this.productId = productId;
    }

    public String getSku() {
        return sku;
    }

    public void setSku(String sku) {
        this.sku = sku;
    }

    public BigDecimal getPrice() {
        return price;
    }

    public void setPrice(BigDecimal price) {
        this.price = price;
    }

    public Integer getStock() {
        return stock;
    }

    public void setStock(Integer stock) {
        this.stock = stock;
    }
}
