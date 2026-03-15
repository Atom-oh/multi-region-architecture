package com.mall.useraccount.dto;

public record LoginResponse(
    String token,
    String tokenType,
    long expiresIn,
    UserResponse user
) {
    public LoginResponse(String token, long expiresIn, UserResponse user) {
        this(token, "Bearer", expiresIn, user);
    }
}
