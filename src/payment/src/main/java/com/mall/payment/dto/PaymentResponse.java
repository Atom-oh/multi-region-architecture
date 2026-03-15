package com.mall.payment.dto;

import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.util.UUID;

import com.mall.payment.model.Payment;
import com.mall.payment.model.PaymentStatus;

public record PaymentResponse(
        UUID id,
        UUID orderId,
        BigDecimal amount,
        String currency,
        PaymentStatus status,
        String paymentMethod,
        String idempotencyKey,
        LocalDateTime createdAt,
        LocalDateTime updatedAt
) {
    public static PaymentResponse from(Payment payment) {
        return new PaymentResponse(
                payment.getId(),
                payment.getOrderId(),
                payment.getAmount(),
                payment.getCurrency(),
                payment.getStatus(),
                payment.getPaymentMethod(),
                payment.getIdempotencyKey(),
                payment.getCreatedAt(),
                payment.getUpdatedAt()
        );
    }
}
