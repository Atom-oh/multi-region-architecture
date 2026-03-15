package com.mall.returns.dto;

import java.util.List;
import java.util.UUID;

public record CreateReturnRequest(
        UUID orderId,
        String userId,
        String reason,
        List<ReturnItemRequest> items) {
}
