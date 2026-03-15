package com.mall.payment.dto;

import java.math.BigDecimal;
import java.util.UUID;

public record CreatePaymentRequest(
        UUID orderId,
        BigDecimal amount,
        String currency,
        String paymentMethod,
        String idempotencyKey
) {
}
