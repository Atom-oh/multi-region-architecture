package com.mall.returns.event;

import java.util.HashMap;
import java.util.Map;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.kafka.core.KafkaTemplate;
import org.springframework.stereotype.Component;

import com.mall.returns.model.ReturnRequest;

@Component
public class ReturnEventPublisher {

    private static final Logger logger = LoggerFactory.getLogger(ReturnEventPublisher.class);

    private final KafkaTemplate<String, Object> kafkaTemplate;

    public ReturnEventPublisher(KafkaTemplate<String, Object> kafkaTemplate) {
        this.kafkaTemplate = kafkaTemplate;
    }

    public void publishReturnCreated(ReturnRequest returnRequest) {
        Map<String, Object> event = buildEvent(returnRequest);
        kafkaTemplate.send("returns.created", returnRequest.getId().toString(), event);
        logger.info("Published returns.created event for return {}", returnRequest.getId());
    }

    public void publishReturnApproved(ReturnRequest returnRequest) {
        Map<String, Object> event = buildEvent(returnRequest);
        kafkaTemplate.send("returns.approved", returnRequest.getId().toString(), event);
        logger.info("Published returns.approved event for return {}", returnRequest.getId());
    }

    public void publishReturnRejected(ReturnRequest returnRequest) {
        Map<String, Object> event = buildEvent(returnRequest);
        kafkaTemplate.send("returns.rejected", returnRequest.getId().toString(), event);
        logger.info("Published returns.rejected event for return {}", returnRequest.getId());
    }

    private Map<String, Object> buildEvent(ReturnRequest returnRequest) {
        Map<String, Object> event = new HashMap<>();
        event.put("return_id", returnRequest.getId().toString());
        event.put("order_id", returnRequest.getOrderId().toString());
        event.put("user_id", returnRequest.getUserId());
        event.put("status", returnRequest.getStatus().name());
        event.put("reason", returnRequest.getReason());
        event.put("item_count", returnRequest.getItems().size());
        return event;
    }
}
