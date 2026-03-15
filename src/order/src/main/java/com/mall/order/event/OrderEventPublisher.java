package com.mall.order.event;

import java.util.Map;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.kafka.core.KafkaTemplate;
import org.springframework.stereotype.Component;

import com.mall.order.dto.OrderResponse;

@Component
public class OrderEventPublisher {

    private static final Logger log = LoggerFactory.getLogger(OrderEventPublisher.class);

    private final KafkaTemplate<String, Object> kafkaTemplate;

    public OrderEventPublisher(KafkaTemplate<String, Object> kafkaTemplate) {
        this.kafkaTemplate = kafkaTemplate;
    }

    public void publishOrderCreated(OrderResponse order) {
        publish("orders.created", order.id().toString(), Map.of(
                "event", "order.created",
                "order", order
        ));
    }

    public void publishOrderConfirmed(OrderResponse order) {
        publish("orders.confirmed", order.id().toString(), Map.of(
                "event", "order.confirmed",
                "order", order
        ));
    }

    public void publishOrderCancelled(OrderResponse order) {
        publish("orders.cancelled", order.id().toString(), Map.of(
                "event", "order.cancelled",
                "order", order
        ));
    }

    private void publish(String topic, String key, Object value) {
        kafkaTemplate.send(topic, key, value)
                .whenComplete((result, ex) -> {
                    if (ex != null) {
                        log.error("Failed to publish to {}: {}", topic, ex.getMessage());
                    } else {
                        log.debug("Published to {} key={}", topic, key);
                    }
                });
    }
}
