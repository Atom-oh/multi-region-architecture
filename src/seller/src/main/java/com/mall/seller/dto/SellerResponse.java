package com.mall.seller.dto;

import java.time.LocalDateTime;
import java.util.UUID;

import com.mall.seller.model.Seller;

public class SellerResponse {
    private UUID id;
    private String businessName;
    private String email;
    private String phone;
    private String status;
    private LocalDateTime createdAt;

    public SellerResponse() {}

    public SellerResponse(Seller seller) {
        this.id = seller.getId();
        this.businessName = seller.getBusinessName();
        this.email = seller.getEmail();
        this.phone = seller.getPhone();
        this.status = seller.getStatus().name();
        this.createdAt = seller.getCreatedAt();
    }

    public UUID getId() {
        return id;
    }

    public void setId(UUID id) {
        this.id = id;
    }

    public String getBusinessName() {
        return businessName;
    }

    public void setBusinessName(String businessName) {
        this.businessName = businessName;
    }

    public String getEmail() {
        return email;
    }

    public void setEmail(String email) {
        this.email = email;
    }

    public String getPhone() {
        return phone;
    }

    public void setPhone(String phone) {
        this.phone = phone;
    }

    public String getStatus() {
        return status;
    }

    public void setStatus(String status) {
        this.status = status;
    }

    public LocalDateTime getCreatedAt() {
        return createdAt;
    }

    public void setCreatedAt(LocalDateTime createdAt) {
        this.createdAt = createdAt;
    }
}
