package com.mall.payment.event;

import java.util.Map;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.kafka.core.KafkaTemplate;
import org.springframework.stereotype.Component;

import com.mall.payment.dto.PaymentResponse;

@Component
public class PaymentEventPublisher {

    private static final Logger log = LoggerFactory.getLogger(PaymentEventPublisher.class);

    private final KafkaTemplate<String, Object> kafkaTemplate;

    public PaymentEventPublisher(KafkaTemplate<String, Object> kafkaTemplate) {
        this.kafkaTemplate = kafkaTemplate;
    }

    public void publishPaymentCompleted(PaymentResponse payment) {
        publish("payments.completed", payment.id().toString(), Map.of(
                "event", "payment.completed",
                "payment", payment
        ));
    }

    public void publishPaymentFailed(PaymentResponse payment) {
        publish("payments.failed", payment.id().toString(), Map.of(
                "event", "payment.failed",
                "payment", payment
        ));
    }

    public void publishPaymentRefunded(PaymentResponse payment) {
        publish("payments.refunded", payment.id().toString(), Map.of(
                "event", "payment.refunded",
                "payment", payment
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
