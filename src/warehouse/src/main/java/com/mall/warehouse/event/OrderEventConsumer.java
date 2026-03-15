package com.mall.warehouse.event;

import java.util.Map;
import java.util.UUID;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.kafka.annotation.KafkaListener;
import org.springframework.stereotype.Component;

import com.mall.warehouse.service.WarehouseService;

@Component
public class OrderEventConsumer {

    private static final Logger logger = LoggerFactory.getLogger(OrderEventConsumer.class);

    private final WarehouseService warehouseService;

    public OrderEventConsumer(WarehouseService warehouseService) {
        this.warehouseService = warehouseService;
    }

    @KafkaListener(topics = "orders.confirmed", groupId = "warehouse-service")
    public void handleOrderConfirmed(Map<String, Object> orderData) {
        logger.info("Received order.confirmed event: {}", orderData);

        try {
            String orderIdStr = orderData.get("order_id") != null
                    ? orderData.get("order_id").toString()
                    : orderData.get("id").toString();
            UUID orderId = UUID.fromString(orderIdStr);

            warehouseService.allocateOrderToNearestWarehouse(orderId);
            logger.info("Auto-allocated order {} to warehouse", orderId);
        } catch (Exception e) {
            logger.error("Failed to allocate order from event: {}", e.getMessage(), e);
        }
    }
}
