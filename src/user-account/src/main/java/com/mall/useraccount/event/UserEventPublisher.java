package com.mall.useraccount.event;

import java.time.Instant;
import java.util.Map;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.kafka.core.KafkaTemplate;
import org.springframework.stereotype.Component;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.mall.useraccount.model.User;

@Component
public class UserEventPublisher {

    private static final Logger logger = LoggerFactory.getLogger(UserEventPublisher.class);
    private static final String TOPIC_USER_REGISTERED = "user.registered";
    private static final String TOPIC_USER_LOGIN = "user.login";

    private final KafkaTemplate<String, String> kafkaTemplate;
    private final ObjectMapper objectMapper;

    public UserEventPublisher(KafkaTemplate<String, String> kafkaTemplate, ObjectMapper objectMapper) {
        this.kafkaTemplate = kafkaTemplate;
        this.objectMapper = objectMapper;
    }

    public void publishUserRegistered(User user) {
        Map<String, Object> event = Map.of(
            "eventType", "user.registered",
            "userId", user.getId().toString(),
            "email", user.getEmail(),
            "name", user.getName(),
            "role", user.getRole().name(),
            "timestamp", Instant.now().toString()
        );
        publish(TOPIC_USER_REGISTERED, user.getId().toString(), event);
    }

    public void publishUserLogin(User user) {
        Map<String, Object> event = Map.of(
            "eventType", "user.login",
            "userId", user.getId().toString(),
            "email", user.getEmail(),
            "timestamp", Instant.now().toString()
        );
        publish(TOPIC_USER_LOGIN, user.getId().toString(), event);
    }

    private void publish(String topic, String key, Map<String, Object> event) {
        try {
            String payload = objectMapper.writeValueAsString(event);
            kafkaTemplate.send(topic, key, payload)
                .whenComplete((result, ex) -> {
                    if (ex != null) {
                        logger.error("Failed to publish event to {}: {}", topic, ex.getMessage());
                    } else {
                        logger.debug("Published event to {} key={}", topic, key);
                    }
                });
        } catch (JsonProcessingException e) {
            logger.error("Failed to serialize event: {}", e.getMessage());
        }
    }
}
