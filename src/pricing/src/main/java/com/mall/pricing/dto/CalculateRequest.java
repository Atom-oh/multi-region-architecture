package com.mall.pricing.dto;

import java.util.List;

public class CalculateRequest {
    private List<CartItem> items;

    public static class CartItem {
        private String sku;
        private int quantity;

        public CartItem() {}

        public CartItem(String sku, int quantity) {
            this.sku = sku;
            this.quantity = quantity;
        }

        public String getSku() {
            return sku;
        }

        public void setSku(String sku) {
            this.sku = sku;
        }

        public int getQuantity() {
            return quantity;
        }

        public void setQuantity(int quantity) {
            this.quantity = quantity;
        }
    }

    public CalculateRequest() {}

    public CalculateRequest(List<CartItem> items) {
        this.items = items;
    }

    public List<CartItem> getItems() {
        return items;
    }

    public void setItems(List<CartItem> items) {
        this.items = items;
    }
}
