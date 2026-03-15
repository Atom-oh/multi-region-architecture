package com.mall.seller.dto;

import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.util.UUID;

import com.mall.seller.model.SellerProduct;

public class SellerProductResponse {
    private UUID id;
    private UUID sellerId;
    private String productId;
    private String sku;
    private BigDecimal price;
    private Integer stock;
    private Boolean active;
    private LocalDateTime createdAt;

    public SellerProductResponse() {}

    public SellerProductResponse(SellerProduct product) {
        this.id = product.getId();
        this.sellerId = product.getSeller().getId();
        this.productId = product.getProductId();
        this.sku = product.getSku();
        this.price = product.getPrice();
        this.stock = product.getStock();
        this.active = product.getActive();
        this.createdAt = product.getCreatedAt();
    }

    public UUID getId() {
        return id;
    }

    public void setId(UUID id) {
        this.id = id;
    }

    public UUID getSellerId() {
        return sellerId;
    }

    public void setSellerId(UUID sellerId) {
        this.sellerId = sellerId;
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

    public Boolean getActive() {
        return active;
    }

    public void setActive(Boolean active) {
        this.active = active;
    }

    public LocalDateTime getCreatedAt() {
        return createdAt;
    }

    public void setCreatedAt(LocalDateTime createdAt) {
        this.createdAt = createdAt;
    }
}
