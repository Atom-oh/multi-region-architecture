package com.mall.seller.dto;

public class RegisterSellerRequest {
    private String businessName;
    private String email;
    private String phone;

    public RegisterSellerRequest() {}

    public RegisterSellerRequest(String businessName, String email, String phone) {
        this.businessName = businessName;
        this.email = email;
        this.phone = phone;
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
}
