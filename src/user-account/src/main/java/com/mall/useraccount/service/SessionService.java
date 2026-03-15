package com.mall.useraccount.service;

import java.time.Duration;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.data.redis.core.RedisTemplate;
import org.springframework.stereotype.Service;

@Service
public class SessionService {

    private static final Logger logger = LoggerFactory.getLogger(SessionService.class);
    private static final String SESSION_PREFIX = "session:";
    private static final Duration SESSION_TTL = Duration.ofHours(24);

    private final RedisTemplate<String, Object> redisTemplate;

    public SessionService(RedisTemplate<String, Object> redisTemplate) {
        this.redisTemplate = redisTemplate;
    }

    public void createSession(String userId, String token) {
        String key = SESSION_PREFIX + userId;
        redisTemplate.opsForValue().set(key, token, SESSION_TTL);
        logger.debug("Session created for user: {}", userId);
    }

    public String getSession(String userId) {
        String key = SESSION_PREFIX + userId;
        Object value = redisTemplate.opsForValue().get(key);
        return value != null ? value.toString() : null;
    }

    public void invalidateSession(String userId) {
        String key = SESSION_PREFIX + userId;
        redisTemplate.delete(key);
        logger.debug("Session invalidated for user: {}", userId);
    }

    public boolean isSessionValid(String userId, String token) {
        String storedToken = getSession(userId);
        return token != null && token.equals(storedToken);
    }
}
