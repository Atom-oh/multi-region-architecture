package com.mall.pricing.dto;

import java.math.BigDecimal;
import java.util.List;

public class CalculateResponse {
    private List<PriceResponse> items;
    private BigDecimal subtotal;
    private BigDecimal totalDiscount;
    private BigDecimal total;
    private String currency;

    public CalculateResponse() {}

    public CalculateResponse(List<PriceResponse> items, BigDecimal subtotal, BigDecimal totalDiscount, BigDecimal total, String currency) {
        this.items = items;
        this.subtotal = subtotal;
        this.totalDiscount = totalDiscount;
        this.total = total;
        this.currency = currency;
    }

    public List<PriceResponse> getItems() {
        return items;
    }

    public void setItems(List<PriceResponse> items) {
        this.items = items;
    }

    public BigDecimal getSubtotal() {
        return subtotal;
    }

    public void setSubtotal(BigDecimal subtotal) {
        this.subtotal = subtotal;
    }

    public BigDecimal getTotalDiscount() {
        return totalDiscount;
    }

    public void setTotalDiscount(BigDecimal totalDiscount) {
        this.totalDiscount = totalDiscount;
    }

    public BigDecimal getTotal() {
        return total;
    }

    public void setTotal(BigDecimal total) {
        this.total = total;
    }

    public String getCurrency() {
        return currency;
    }

    public void setCurrency(String currency) {
        this.currency = currency;
    }
}
