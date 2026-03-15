package com.mall.useraccount.dto;

import java.time.Instant;
import java.util.UUID;

import com.mall.useraccount.model.User;

public record UserResponse(
    UUID id,
    String email,
    String name,
    String role,
    boolean active,
    Instant createdAt
) {
    public static UserResponse from(User user) {
        return new UserResponse(
            user.getId(),
            user.getEmail(),
            user.getName(),
            user.getRole().name(),
            user.isActive(),
            user.getCreatedAt()
        );
    }
}
